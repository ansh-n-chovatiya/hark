import AppKit
import ApplicationServices
import HarkCore
import HarkMac
import os

private let logger = Logger(subsystem: "dev.hark.app", category: "app")

/// Writes a log line whenever the main thread stops answering for a second or more. Key presses
/// and the panel both wait on the main thread, so a stall there looks like a stuck panel; the
/// log says when it happened and for how long.
private final class StallLog: Sendable {
    private static let checkEvery: DispatchTimeInterval = .milliseconds(500)
    private static let worthLogging: Duration = .seconds(1)

    private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "hark.stall-log", qos: .utility))
    private let isWaiting = OSAllocatedUnfairLock(initialState: false)

    func start() {
        timer.schedule(deadline: .now() + Self.checkEvery, repeating: Self.checkEvery)
        timer.setEventHandler { [isWaiting] in
            let alreadyWaiting = isWaiting.withLock { waiting in
                defer { waiting = true }
                return waiting
            }
            guard !alreadyWaiting else { return }
            let asked = ContinuousClock.now
            DispatchQueue.main.async {
                isWaiting.withLock { $0 = false }
                let waited = ContinuousClock.now - asked
                if waited >= Self.worthLogging {
                    logger.error("the main thread did not answer for \(waited.components.seconds, privacy: .public) s")
                }
            }
        }
        timer.resume()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = Overlay()
    private let commandBar = CommandBar()
    private let dictationIndicator = DictationIndicator()
    private let transcriber = ParakeetTranscriber { status in
        logger.notice("speech: \(status.isEmpty ? "Parakeet ready" : status, privacy: .public)")
    }
    private let clock = ContinuousClock()
    private var menuBar: MenuBar?
    private var pipeline: Pipeline?
    private var hotkey: Hotkey?
    private var typeHotkey: Hotkey?
    private var dictationHotkey: Hotkey?
    private var isDictating = false
    private var taps = DictationTaps()
    /// True from the moment dictation stops until its words are typed: the speech recorder is still in use.
    private var dictationBusy = false
    private var tapWindow: Task<Void, Never>?
    private var dictationWatch: Task<Void, Never>?
    private var clipboardWatcher: ClipboardWatcher?
    private var clipSource: ClipSource?
    private var settings: SettingsWindow?
    private var config = Config()
    private let log = TimingLog(url: Paths.timings)
    private let activityLog = ActivityLog(url: Paths.activity)
    private lazy var learning = LearningCenter(
        activity: activityLog, history: log, store: LearningStore(url: Paths.learning),
        reports: WrongLog(url: Paths.wrong))
    private var recorder: ActivityRecorder?
    private var suggestionTimer: Timer?
    private var capture: Task<Bool, Never>?
    private var isHolding = false
    private var pressedAt: ContinuousClock.Instant?
    private var lastHeard = ""
    private var holdWatch: Task<Void, Never>?
    private let stallLog = StallLog()

    /// No command takes this long to say. A hold that lasts longer means the key's release was
    /// missed, and listening has to end on its own.
    private static let longestHold: Duration = .seconds(45)

    /// Turning the recording into words takes a fraction of a second. Past this something has
    /// stalled, and a panel stuck on "Listening" is worse than being asked to say it again.
    private static let longestWaitForWords: Duration = .seconds(5)

    /// Nobody says a command in less time than this.
    private static let tapLimit: Duration = .milliseconds(250)

    func applicationDidFinishLaunching(_ notification: Notification) {
        dictationIndicator.onCancel = { [weak self] in self?.dictationCancelled() }
        dictationIndicator.onFinish = { [weak self] in self?.finishDictation() }
        menuBar = MenuBar()
        if CommandLine.arguments.contains("--demo-overlay") {
            overlay.runDemo()
            return
        }

        NetworkStatus.shared.start()
        config = loadConfig()
        startLearning()
        install(config)
        // Finding AI tools already on the Mac asks a login shell, so it is done away from the main thread;
        // the models are set up again once it is known what was found.
        Task.detached { [weak self] in
            guard !ModelCLIs.discover().isEmpty else { return }
            await MainActor.run { if let self { self.install(self.config) } }
        }
        commandBar.onSubmit = { [weak self] text in self?.runTyped(text) }
        menuBar?.onTypeCommand = { [weak self] in
            self?.commandBar.show()
            if let config = self?.config { ModelWarmUp.start(for: config) }
        }
        menuBar?.onSettings = { [weak self] in self?.showSettings() }
        menuBar?.onLearning = { [weak self] in self?.showSettings(.learning) }
        overlay.onPick = { [weak self] number in
            Task {
                guard let self, let pipeline = self.pipeline else { return }
                self.present(await pipeline.pick(number))
            }
        }

        Task { await startClipboardMemory() }
        Task {
            do {
                try await transcriber.prepare()
                logger.notice("speech ready")
            } catch {
                logger.error("speech not ready: \(error.localizedDescription, privacy: .public)")
                overlay.show(.error(error.localizedDescription))
            }
            for await text in transcriber.partials where isHolding {
                lastHeard = text
                overlay.show(.hearing(text))
            }
        }
        Task { await startHotkey(key: config.hotkey) }
        stallLog.start()
    }

    /// Starts noting which apps and sites come to the front, sets up folders on the first run, and keeps
    /// the menu's "Hark noticed" line up to date. Does nothing while learning is off.
    private func startLearning() {
        log.trim()
        activityLog.prune()
        if learning.setUpIfNeeded(&config) {
            try? ConfigStore.save(config)
            logger.notice("set up folders and projects on first run")
        }
        let recorder = ActivityRecorder(log: activityLog, browsers: Registry.browserSources()) { [weak self] in
            self?.config.learns ?? false
        }
        recorder.start()
        self.recorder = recorder
        let timer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reviewAndRefresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        suggestionTimer = timer
        Task {
            try? await Task.sleep(for: .seconds(8))
            reviewAndRefresh()
        }
    }

    /// Lets the model review failed commands when one is due, then updates the menu's count.
    private func reviewAndRefresh() {
        let center = learning
        let current = config
        Task {
            await LearningReview.runIfDue(config: current, center: center)
            refreshSuggestionHint()
        }
    }

    private func refreshSuggestionHint() {
        let center = learning
        let current = config
        Task {
            let found = await Task.detached { center.snapshot(config: current).suggestions }.value
            let shown = await SuggestionProof.shared.verified(found, config: current)
            menuBar?.setSuggestionCount(shown.count)
        }
    }

    /// Builds the pipeline for these settings. Called at launch and again whenever they change.
    private func install(_ config: Config) {
        let pipeline = Pipeline(
            config: config, sources: Registry.sources(config: config), log: log,
            saveRoutine: { [weak self] routine in await self?.keep(routine) },
            saveName: { [weak self] said, meaning in await self?.keepName(said, meaning) },
            announce: { [weak self] result in await self?.announce(result) })
        self.pipeline = pipeline
        Task {
            if let clipSource { await pipeline.add(clipSource) }
            // Not awaited by the caller: a source can sit on a macOS permission prompt for seconds.
            await pipeline.prepareForCommand()
        }
    }

    /// Adds a routine Hark wrote (a saved setup) to the settings, replacing one of the same name.
    private func keep(_ routine: Routine) {
        var changed = config
        changed.routines.removeAll { $0.name.caseInsensitiveCompare(routine.name) == .orderedSame }
        changed.routines.append(routine)
        apply(changed)
    }

    /// Teaches a name from "remember that as ...".
    private func keepName(_ said: String, _ meaning: String) {
        var changed = config
        changed.aliases[said] = meaning
        apply(changed)
    }

    /// For a result that arrives after its command has returned, such as a routine left to run.
    private func announce(_ result: String) {
        NSSound(named: "Glass")?.play()
        overlay.show(.answer(result))
    }

    private func showSettings(_ section: SettingsSection = .general) {
        if settings == nil {
            settings = SettingsWindow(config: config, log: log, learning: learning) { [weak self] changed in self?.apply(changed) }
        }
        // The file may have changed since the window was made: a saved setup, or a hand edit.
        settings?.reload(config)
        settings?.show(section)
    }

    private func apply(_ changed: Config) {
        let keyChanged = changed.hotkey != config.hotkey
        // Only a key that was there and has just been emptied is removed from the Keychain.
        let clearedKey = changed.modelKey.isEmpty && !config.modelKey.isEmpty
        config = changed
        do {
            try ConfigStore.save(changed, clearing: clearedKey)
        } catch {
            overlay.show(.error("Your settings could not be saved: \(error.localizedDescription)"))
        }
        install(changed)
        refreshSuggestionHint()
        guard keyChanged else {
            startTypeKey()
            return
        }
        hotkey?.stop()
        hotkey = nil
        Task { await startHotkey(key: changed.hotkey) }
    }

    private func startClipboardMemory() async {
        do {
            let clipboard = try Registry.clipboard(config: config)
            clipboard.watcher.start()
            clipboardWatcher = clipboard.watcher
            clipSource = clipboard.source
            await pipeline?.add(clipboard.source)
            logger.notice("clipboard memory ready")
        } catch {
            logger.error("clipboard memory is off: \(error.localizedDescription, privacy: .public)")
            overlay.show(.error("Clipboard memory is off: \(error.localizedDescription)"))
        }
    }

    private func loadConfig() -> Config {
        do {
            return try ConfigStore.load()
        } catch {
            ConfigStore.keepUnreadableFile()
            overlay.show(.error("The settings file could not be read, so defaults are in use. Your file was kept as config.json.unreadable."))
            return Config()
        }
    }

    private func startHotkey(key: String) async {
        if !AXIsProcessTrusted() {
            logger.notice("waiting for the accessibility permission")
            menuBar?.setStatus("Turn on Accessibility for Hark…") { Permissions.openSettings(for: .accessibility) }
            showSettings(.permissions)
            // The prompt option also adds Hark to the Accessibility list, so the user only flips a switch.
            // The key is spelled out because the SDK's constant is a global var Swift 6 will not read.
            let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(prompt)
            while !AXIsProcessTrusted() {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        let hotkey = Hotkey(
            key: key,
            onDown: { [weak self] in Self.onMain { self?.keyDown() } },
            onUp: { [weak self] in Self.onMain { self?.keyUp() } },
            onCancel: { [weak self] in Self.onMain { self?.keyCancelled() } })
        do {
            try hotkey.start()
            self.hotkey = hotkey
            logger.notice("key ready: \(key, privacy: .public)")
            startTypeKey()
            let typing = config.typeKey.isEmpty ? "" : ", tap \(Self.spokenName(ofKey: config.typeKey)) to type"
            let dictating = config.dictationKey.isEmpty
                ? "" : ", hold \(Self.spokenName(ofKey: config.dictationKey)) to dictate"
            menuBar?.setStatus("Hold \(Self.spokenName(ofKey: key)) to speak\(typing)\(dictating)")
        } catch {
            logger.error("key not ready: \(error.localizedDescription, privacy: .public)")
            menuBar?.setStatus(error.localizedDescription)
            overlay.show(.error(error.localizedDescription))
        }
    }

    /// Typing has its own key so that it can never be mistaken for the start of speaking. Used
    /// inside a shortcut the key does nothing here, because Hotkey reports that as a cancel.
    private func startTypeKey() {
        startDictationKey()
        typeHotkey?.stop()
        typeHotkey = nil
        guard !config.typeKey.isEmpty, config.typeKey != config.hotkey else { return }
        let key = Hotkey(
            key: config.typeKey,
            onDown: {},
            onUp: { [weak self] in Self.onMain { self?.commandBar.show() } },
            onCancel: {})
        do {
            try key.start()
            typeHotkey = key
        } catch {
            logger.error("typing key not ready: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Hands a key event to the main thread in the order it happened. Separate tasks carry no such
    /// promise: after a quick tap the release could run before the press, leaving the panel on
    /// "Listening" with nothing held.
    private nonisolated static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(work) }
    }

    /// "rightOption" reads as "right Option" in the menu.
    private static func spokenName(ofKey key: String) -> String {
        for side in ["right", "left"] where key.hasPrefix(side) && key.count > side.count {
            return "\(side) \(key.dropFirst(side.count))"
        }
        return key.uppercased()
    }

    /// Dictation has its own key too: holding it types what is said instead of acting on it.
    private func startDictationKey() {
        dictationHotkey?.stop()
        dictationHotkey = nil
        let key = config.dictationKey
        guard !key.isEmpty, key != config.hotkey, key != config.typeKey else { return }
        let hotkey = Hotkey(
            key: key,
            onDown: { [weak self] in Self.onMain { self?.dictationDown() } },
            onUp: { [weak self] in Self.onMain { self?.dictationUp() } },
            onCancel: { [weak self] in Self.onMain { self?.dictationCancelled() } })
        do {
            try hotkey.start()
            dictationHotkey = hotkey
        } catch {
            logger.error("dictation key not ready: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Nobody dictates for longer than this; a hold past it means the release was missed.
    private static let longestDictation: Duration = .seconds(120)

    /// The dictation key is held (talk while it is down), or tapped twice (hands-free, one tap to finish).
    private func dictationDown() {
        guard !isHolding, !dictationBusy else { return }
        switch taps.keyDown(at: Date()) {
        case .start:
            beginDictation()
        case .becomeHandsFree:
            tapWindow?.cancel()
            dictationIndicator.show(.handsFree)
        case .finish:
            finishDictation()
        default:
            break
        }
    }

    private func dictationUp() {
        switch taps.keyUp(at: Date()) {
        case .finish:
            finishDictation()
        case .wait:
            // A quick tap: keep listening for a moment, in case a second tap follows.
            tapWindow?.cancel()
            tapWindow = Task { [weak self] in
                try? await Task.sleep(for: .seconds(DictationTaps.doubleTapWindow))
                guard !Task.isCancelled else { return }
                self?.tapWindowClosed()
            }
        default:
            break
        }
    }

    private func tapWindowClosed() {
        if taps.windowClosed() == .cancel { dictationCancelled() }
    }

    private func beginDictation() {
        // One recording at a time: the speech model is shared with commands.
        isDictating = true
        dictationWatch?.cancel()
        dictationWatch = Task { [weak self] in await self?.watchDictation() }
        commandBar.hide()
        overlay.show(.hidden)
        dictationIndicator.show(.listening)
        capture = Task {
            do {
                try await transcriber.start()
                return true
            } catch {
                dictationIndicator.show(.error(error.localizedDescription))
                return false
            }
        }
    }

    private func watchDictation() async {
        let started = clock.now
        while !Task.isCancelled, isDictating {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, isDictating else { return }
            // A missed release is only looked for while the key is meant to be held.
            if taps.mode == .holding, Self.isPhysicallyUp(config.dictationKey) {
                dictationUp()
                return
            }
            if clock.now - started > Self.longestDictation {
                // Long enough: what was said is typed, not thrown away.
                finishDictation()
                return
            }
        }
    }

    /// Turns what was said into text and types it where the cursor is.
    private func finishDictation() {
        guard isDictating else { return }
        isDictating = false
        dictationBusy = true
        taps.reset()
        tapWindow?.cancel()
        dictationWatch?.cancel()
        dictationIndicator.show(.typing)
        Task {
            defer { dictationBusy = false }
            do {
                guard let heard = try await wordsFromRecording(timeout: .seconds(20)) else {
                    dictationIndicator.show(.error("I could not hear that. Please try again."))
                    return
                }
                let text = Dictation.tidy(heard)
                guard !text.isEmpty else {
                    dictationIndicator.show(.hidden)
                    return
                }
                let words = text.split(separator: " ").count
                menuBar?.setLastDictation(text)
                do {
                    try await TextTyper.type(text)
                    logger.notice("dictated \(words, privacy: .public) words")
                    dictationIndicator.show(.typed(words))
                } catch TextTyperError.passwordField {
                    // Never copied: a password box is the one place the words must not end up.
                    dictationIndicator.show(.error(TextTyperError.passwordField.localizedDescription))
                } catch {
                    // Nowhere to type: keep what was said on the clipboard, so it is not lost.
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    logger.notice("dictated \(words, privacy: .public) words to the clipboard")
                    dictationIndicator.show(.copied(words))
                }
            } catch {
                dictationIndicator.show(.error(error.localizedDescription))
            }
        }
    }

    private func dictationCancelled() {
        isDictating = false
        taps.reset()
        tapWindow?.cancel()
        dictationWatch?.cancel()
        dictationIndicator.show(.hidden)
        // The recording to throw away is taken now: a tap a moment later starts a new one, which must not be ended.
        let recording = capture
        dictationBusy = true
        Task {
            defer { dictationBusy = false }
            guard await recording?.value == true else { return }
            _ = try? await transcriber.finish()
        }
    }

    private func keyDown() {
        guard !isDictating, !dictationBusy else { return }
        isHolding = true
        lastHeard = ""
        pressedAt = clock.now
        holdWatch?.cancel()
        holdWatch = Task { [weak self] in await self?.watchHold() }
        commandBar.hide()
        overlay.show(.listening)
        // An AI tool on the Mac takes a moment to start; the user is speaking for a while, so start it now.
        ModelWarmUp.start(for: config)
        Task { [pipeline, transcriber] in
            guard let pipeline else { return }
            await pipeline.prepareForCommand()
            await transcriber.setVocabulary(await pipeline.vocabulary())
        }
        capture = Task {
            do {
                try await transcriber.start()
                return true
            } catch {
                overlay.show(.error(error.localizedDescription))
                return false
            }
        }
    }

    /// Ends listening if the key is no longer physically down. macOS can fail to report a key's
    /// release (while another program is sending its own key presses, for one), and without this
    /// the panel would sit on "Listening" with nothing held.
    private func watchHold() async {
        let started = clock.now
        while !Task.isCancelled, isHolding {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, isHolding else { return }
            if Self.isPhysicallyUp(config.hotkey) {
                logger.notice("the key is up but its release was not reported; carrying on as if it had been")
                keyUp()
                return
            }
            if clock.now - started > Self.longestHold {
                logger.error("listening ran past its limit and was stopped")
                keyCancelled()
                overlay.show(.error("Listening stopped. Hold the key again to speak."))
                return
            }
        }
    }

    /// Whether the named key is certainly not being held. Option, Command, Control and Shift are
    /// reported by macOS as a state, not as keys, so they are read from the modifier state (which
    /// does not tell left from right: the other side being held counts as held). An unknown name
    /// answers false, which leaves the reported release in charge.
    private static func isPhysicallyUp(_ key: String) -> Bool {
        let name = key.lowercased()
        let modifiers: [(String, CGEventFlags)] = [
            ("option", .maskAlternate), ("command", .maskCommand), ("control", .maskControl), ("shift", .maskShift),
            ("fn", .maskSecondaryFn),
        ]
        if let flag = modifiers.first(where: { name.hasSuffix($0.0) })?.1 {
            return !CGEventSource.flagsState(.hidSystemState).contains(flag)
        }
        guard let code = functionKeyCodes[name] else { return false }
        return !CGEventSource.keyState(.hidSystemState, key: code)
    }

    private static let functionKeyCodes: [String: CGKeyCode] = [
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
    ]

    private func keyUp() {
        guard isHolding else { return }
        isHolding = false
        holdWatch?.cancel()
        let released = clock.now
        // Too short to have said anything: a brush of the key, not a command.
        if let pressedAt, released - pressedAt < Self.tapLimit {
            keyCancelled()
            return
        }
        // The release is acknowledged at once, so the panel never looks as if the key is still held.
        overlay.show(.working(lastHeard))
        Task {
            do {
                guard let text = try await wordsFromRecording() else {
                    logger.error("the recording did not turn into words in time")
                    overlay.show(.error("I could not hear that. Please try again."))
                    return
                }
                guard !text.isEmpty else {
                    overlay.show(.hidden)
                    return
                }
                let waited = clock.now - released
                let transcribeMs = Double(waited.components.seconds) * 1000
                    + Double(waited.components.attoseconds) / 1e15
                // The final words can differ from the live ones, which come from a quicker, rougher recogniser.
                overlay.show(.working(text))
                await carryOut(text, transcribeMs: transcribeMs, heardBy: transcriber.source)
            } catch {
                overlay.show(.error(error.localizedDescription))
            }
        }
    }

    /// The words of the recording just finished, or nil if they did not arrive in time. An empty
    /// string means nothing was said.
    private func wordsFromRecording(timeout: Duration = longestWaitForWords) async throws -> String? {
        try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask { [capture, transcriber] in
                guard await capture?.value == true else { return "" }
                return try await transcriber.finish()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }

    private func carryOut(_ text: String, transcribeMs: Double, heardBy source: String) async {
        guard let pipeline else { return }
        menuBar?.setLastCommand(text)
        let outcome = await pipeline.run(transcript: text, transcribeMs: transcribeMs)
        logger.notice("command finished: \(outcome.logLabel, privacy: .public), from \(source, privacy: .public)")
        present(outcome)
    }

    /// A typed command takes the same path as a spoken one, minus the hearing.
    private func runTyped(_ text: String) {
        overlay.show(.working(text))
        Task {
            await pipeline?.prepareForCommand()
            await carryOut(text, transcribeMs: 0, heardBy: "typing")
        }
    }

    private func keyCancelled() {
        isHolding = false
        holdWatch?.cancel()
        overlay.show(.hidden)
        Task {
            guard await capture?.value == true else { return }
            // The audio is thrown away on purpose, so a failure to finish it changes nothing.
            _ = try? await transcriber.finish()
        }
    }

    private func present(_ outcome: Outcome) {
        switch outcome {
        case .done(let text): overlay.show(.result(text))
        case .answer(let text): overlay.show(.answer(text))
        case .choose(let matches): overlay.show(.choices(matches))
        case .confirm(let question): overlay.show(.confirm(question))
        case .notUnderstood(let text), .failed(let text): overlay.show(.error(text))
        }
    }
}

private extension Outcome {
    var logLabel: String {
        switch self {
        case .done, .answer: "done"
        case .choose: "choose"
        case .confirm: "confirm"
        case .notUnderstood: "not understood"
        case .failed(let message): "failed: \(message)"
        }
    }
}

func reviewFailures(save: Bool) async -> Int32 {
    ModelCLIs.discover()
    let config = (try? ConfigStore.load()) ?? Config()
    let center = LearningCenter(
        activity: ActivityLog(url: Paths.activity), history: TimingLog(url: Paths.timings),
        store: LearningStore(url: Paths.learning), reports: WrongLog(url: Paths.wrong))
    var phrases = center.reviewInput(config: config, now: .distantFuture)
    if phrases.isEmpty { phrases = Learner.deadEnds(history: TimingLog(url: Paths.timings).all()).map(\.phrase) }
    print("failed commands to review: \(phrases.count)")
    for phrase in phrases { print("  \u{201C}\(phrase)\u{201D}") }
    guard !phrases.isEmpty else { return 0 }
    do {
        let proposed = try await FailureReviewer.ask(phrases: phrases, config: config)
        print("the model proposed \(proposed.count):")
        var proven: [Suggestion] = []
        for suggestion in proposed {
            let worked = await SuggestionProof.shared.works(suggestion, config: config)
            print("  \(worked ? "works      " : "no effect  ") \(suggestion.said ?? "") -> \(suggestion.meant ?? "")")
            if worked { proven.append(suggestion) }
        }
        if save {
            center.saveReview(proven)
            print("saved \(proven.count)")
        }
        return 0
    } catch {
        print("the review failed: \(error.localizedDescription)")
        return 1
    }
}

/// Keeps the pill from `--show-dictation` alive while it is on screen.
private enum Showing {
    nonisolated(unsafe) static var indicator: AnyObject?
    nonisolated(unsafe) static var settings: AnyObject?
}

func runCommandLine(_ flag: String, _ values: [String]) async -> Int32 {
    switch flag {
    case "--median":
        guard let verb = values.first else {
            print("usage: hark --median <verb>")
            return 2
        }
        guard let value = TimingLog(url: Paths.timings).medianTotalMs(verb: verb) else {
            print("no timings logged for \(verb)")
            return 1
        }
        print(String(format: "%.0f ms", value))
        return 0
    case "--say":
        guard let text = values.first else {
            print("usage: hark --say \"<command>\"")
            return 2
        }
        return await say(text, dryRun: values.contains("--dry"), answerYes: values.contains("--yes"))
    case "--eval":
        guard let path = values.first else {
            print("usage: hark --eval <file> [--local [--model <name>] | --rules-only [--min <percent>]] [--pause <seconds>]")
            return 2
        }
        let model = values.firstIndex(of: "--model").flatMap { values.indices.contains($0 + 1) ? values[$0 + 1] : nil }
        let rulesOnly = values.contains("--rules-only")
        return await evaluate(
            path, local: values.contains("--local"), localModel: model, rulesOnly: rulesOnly,
            minimum: number(after: "--min", in: values), pause: number(after: "--pause", in: values) ?? (rulesOnly ? 0 : 4))
    case "--wrong":
        let entries = WrongLog(url: Paths.wrong).all()
        if entries.isEmpty { print("no commands have been marked as wrong") }
        for entry in entries {
            print("heard:  \(entry.heard)\ndid:    \(entry.did)\nwanted: \(entry.wanted.isEmpty ? "(not said)" : entry.wanted)\n")
        }
        return 0
    case "--tool":
        guard values.count >= 2 else {
            print("usage: hark --tool <name> '<arguments as JSON>'")
            return 2
        }
        return await callTool(named: values[0], json: values[1])
    case "--review-failures":
        // Runs the failed-command review now against the real history and model, and says what each step did.
        return await reviewFailures(save: values.contains("--save"))
    case "--proof":
        guard values.count >= 2 else {
            print("usage: hark --proof \"<what was said>\" \"<what it means>\"")
            return 2
        }
        let config = (try? ConfigStore.load()) ?? Config()
        let name = Learner.alias(said: values[0], meant: values[1])
        let suggestion = Suggestion(
            id: "proof", kind: .name, title: "", detail: "", said: name?.said ?? values[0], meant: name?.meant ?? values[1],
            example: values[0])
        let worked = await SuggestionProof.shared.works(suggestion, config: config)
        print(worked ? "works: Hark would act on \"\(values[0])\" with that name" : "does not work")
        return worked ? 0 : 1
    case "--models":
        // Lists the models in the order they are tried and times a tiny question to each on its own.
        ModelCLIs.discover()
        let config = (try? ConfigStore.load()) ?? Config()
        guard let chain = ModelSetup.make(for: config).chain else {
            print("No model is set up.")
            return 1
        }
        let clock = ContinuousClock()
        for choice in chain.choices {
            let started = clock.now
            do {
                _ = try await choice.model.reply(to: [.user("Reply with the single word ok.")], tools: [])
                let took = clock.now - started
                print("\(choice.label)\(choice.isStandIn ? " (small stand-in)" : ""): answered in \(took)")
            } catch {
                let took = clock.now - started
                print("\(choice.label): failed after \(took): \(error.localizedDescription.prefix(140))")
            }
        }
        return 0
    case "--window-counts":
        // How many controls of each kind the app in front exposes. Counts only, never labels.
        if let found = await FrontWindow.counts() {
            print("\(found.app): \(found.kinds.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", "))")
        } else {
            print("No app is in front, or Accessibility is not allowed.")
        }
        return 0
    case "--typing-check":
        // Where the app in front would take dictation: the answer only, nothing is typed. Waits a few seconds so
        // the app to check can be brought to the front first.
        let wait = number(after: "--wait", in: values) ?? 0
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        print(TextTyper.verdict())
        return 0
    case "--permissions":
        for permission in Permission.allCases { print("\(permission.rawValue): \(Permissions.status(permission).rawValue)") }
        let chrome = NSAppleEventDescriptor(bundleIdentifier: Registry.browserSources().first?.bundleID ?? "")
        let raw = AEDeterminePermissionToAutomateTarget(chrome.aeDesc, typeWildCard, typeWildCard, false)
        print("chrome running: \(!NSRunningApplication.runningApplications(withBundleIdentifier: Registry.browserSources().first?.bundleID ?? "").isEmpty), raw code: \(raw)")
        return 0
    case "--show-dictation":
        // Puts the dictation pill on screen for a few seconds, to see it where the real one appears.
        let seconds = number(after: "--seconds", in: values) ?? 6
        await MainActor.run {
            NSApplication.shared.setActivationPolicy(.accessory)
            let indicator = DictationIndicator()
            indicator.show(.listening)
            Showing.indicator = indicator
        }
        try? await Task.sleep(for: .seconds(seconds))
        return 0
    case "--show-settings":
        // Shows the real settings window with sample data and prints its window number for `screencapture -l`.
        let section = values.first.flatMap(SettingsSection.init(rawValue:)) ?? .general
        let seconds = number(after: "--seconds", in: values) ?? 15
        await MainActor.run {
            let shown = SettingsWindow.showSample(section)
            Showing.settings = shown.controller
            print("window \(shown.number)")
            fflush(stdout)
        }
        try? await Task.sleep(for: .seconds(seconds))
        return 0
    case "--render-settings":
        guard let folder = values.first else {
            print("usage: hark --render-settings <folder>")
            return 2
        }
        do {
            try await MainActor.run { try SettingsWindow.renderPreviews(to: URL(fileURLWithPath: folder)) }
            return 0
        } catch {
            print(error.localizedDescription)
            return 1
        }
    case "--transcribe":
        guard let path = values.first else {
            print("usage: hark --transcribe <audio file>")
            return 2
        }
        do {
            let result = try await ParakeetTranscriber().transcribe(file: URL(fileURLWithPath: path))
            print(result.text)
            print(String(format: "%.0f ms", result.ms))
            return 0
        } catch {
            print(error.localizedDescription)
            return 1
        }
    default:
        print("unknown option \(flag)")
        return 2
    }
}

/// With `dryRun` the command is worked out and reported but nothing on the Mac changes.
/// Calls one of the model's tools directly and prints what the model would read back, for
/// working out why a command went wrong. The safety fences that depend on the spoken command
/// are not applied here, so this is a developer's check, not a way to use Hark.
func callTool(named name: String, json: String) async -> Int32 {
    let tools: [any Tool] = [
        ListMenuTool(), ClickMenuTool(), PressKeysTool(), OpenPathTool(), OpenAddressTool(),
        SetVolumeTool(), SetMuteTool(), SetAppearanceTool(), ArrangeWindowTool(),
    ] + ScreenTools.all()
    guard let tool = tools.first(where: { $0.spec.name == name }) else {
        print("no tool named \(name); there are: \(tools.map(\.spec.name).joined(separator: ", "))")
        return 2
    }
    do {
        let arguments = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        print("would: \(tool.describe(arguments)) [\(tool.kind(for: arguments))]")
        print(try await tool.call(arguments).output)
        return 0
    } catch {
        print("error: \(error.localizedDescription)")
        return 1
    }
}

func number(after flag: String, in values: [String]) -> Double? {
    guard let index = values.firstIndex(of: flag), values.indices.contains(index + 1) else { return nil }
    return Double(values[index + 1])
}

/// Scores Hark on a file of commands. With `local` only a model on this Mac is used: the one in
/// the settings, or `localModel` to try another.
func evaluate(
    _ path: String, local: Bool, localModel: String?, rulesOnly: Bool, minimum: Double?, pause: Double
) async -> Int32 {
    ModelCLIs.discover()
    do {
        var config = try ConfigStore.load()
        if rulesOnly {
            // No model of any kind, so the score depends only on the rules and is the same on every Mac.
            config = Config()
            config.useModel = false
            config.fallbackModel = ""
        } else if local {
            config.modelURL = config.fallbackModelURL
            config.model = localModel ?? config.fallbackModel
            config.modelKey = ""
        }
        let evaluation = try Evaluation.load(from: URL(fileURLWithPath: path))
        let results = await evaluation.run(config: config, pause: .seconds(pause)) { result in
            let mark = result.passed ? "ok  " : "MISS"
            print(String(format: "%@ %4.1fs  %@\n            -> %@", mark, result.seconds, result.say, String(result.got.prefix(110))))
        }
        let passed = results.filter(\.passed).count
        let times = results.map(\.seconds).sorted()
        print(String(
            format: "\n%d of %d right (%.0f%%) · median %.1fs · slowest %.1fs · models tried: %@",
            passed, results.count, 100 * Double(passed) / Double(max(results.count, 1)),
            times[times.count / 2], times.last ?? 0,
            rulesOnly ? "none (rules only)" : local ? "\(config.model) on this Mac"
                : (ModelSetup.make(for: config).chain?.choices.map(\.label).joined(separator: ", then ") ?? "none")))
        let score = 100 * Double(passed) / Double(max(results.count, 1))
        if let minimum, score < minimum {
            print(String(format: "Below the required %.0f%%.", minimum))
            return 1
        }
        return 0
    } catch {
        print(error.localizedDescription)
        return 1
    }
}

/// `answerYes` answers a yes-or-no question as the user pressing 1 would.
func say(_ text: String, dryRun: Bool, answerYes: Bool) async -> Int32 {
    ModelCLIs.discover()
    let config: Config
    do {
        config = try ConfigStore.load()
    } catch {
        print("could not read \(Paths.config.path): \(error.localizedDescription)")
        return 1
    }
    // A dry run is a test, so it stays out of the log that speed and accuracy are judged from.
    let logURL = dryRun ? FileManager.default.temporaryDirectory.appending(path: "hark-dry-run.jsonl") : Paths.timings
    let log = TimingLog(url: logURL)
    let pipeline = Pipeline(config: config, sources: Registry.sources(config: config), log: log, dryRun: dryRun)
    await pipeline.refreshSources()
    var outcome = await pipeline.run(transcript: text, transcribeMs: 0)
    if answerYes, case .confirm(let question) = outcome {
        print("Asks: \(question) (answered yes)")
        outcome = await pipeline.pick(1)
    }

    switch outcome {
    case .done(let message), .notUnderstood(let message), .failed(let message), .answer(let message):
        print(message)
    case .confirm(let question):
        print("Asks: \(question)")
    case .choose(let matches):
        for (index, match) in matches.enumerated() {
            print("\(index + 1). \(match.item.title)  \(match.item.detail)  \(match.item.owner)")
        }
    }
    if let timings = await pipeline.lastTimings {
        print(String(
            format: "parse %.2f ms · match %.2f ms · model %.0f ms · act %.1f ms · total %.1f ms",
            timings.parseMs, timings.matchMs, timings.modelMs ?? 0, timings.actMs, timings.totalMs))
        if let tools = timings.tools, !tools.isEmpty { print("tools: \(tools.joined(separator: ", "))") }
    }
    if CommandLine.arguments.contains("--trace") {
        for message in await pipeline.lastConversation {
            switch message {
            case .system: break
            case .user(let text): print("USER   \(text.suffix(160))")
            case .assistant(let text, let calls):
                print("MODEL  \(text ?? "")" + calls.map { " \($0.name)(\($0.arguments))" }.joined())
            case .tool(_, let name, let output): print("TOOL   \(name): \(output.prefix(300))")
            }
        }
    }
    // Reading the log waits for the pending write, so the line is on disk before the process ends.
    _ = log.all()
    switch outcome {
    case .done, .answer: return 0
    default: break
    }
    return 1
}

let arguments = Array(CommandLine.arguments.dropFirst())
if let flag = arguments.first, flag.hasPrefix("--"), flag != "--demo-overlay" {
    Task {
        exit(await runCommandLine(flag, Array(arguments.dropFirst())))
    }
    // A real run loop, not dispatchMain: macOS only tells a process which apps are running
    // through its main run loop, and a command that opens an app then needs to find it.
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
