import AVFoundation
import HarkCore
import Speech
import Synchronization

/// On-device speech to text with `SpeechAnalyzer`.
///
/// `prepare()` loads the model, builds the recogniser for the first command and, when
/// `keepMicrophoneOpen` is true, starts the microphone into a short ring buffer so `start()`
/// costs nothing and the 200 ms before the key went down are not lost. The microphone
/// indicator in the menu bar then stays lit for as long as the app runs; pass `false` to open
/// the microphone only while the key is held, at the price of the device's start-up time.
public final class AppleTranscriber: Transcriber {
    public let partials: AsyncStream<String>

    private let preferredLocale: Locale
    private let keepMicrophoneOpen: Bool
    private let onModelDownloadProgress: (@Sendable (Double) -> Void)?
    private let partialsContinuation: AsyncStream<String>.Continuation
    private let state = Mutex(State())

    private static let preRollSeconds = 0.2
    private static let trailingAudioLimit = Duration.milliseconds(150)

    private struct State {
        var model: SpeechModel?
        var microphone: MicrophoneInput?
        var standby: Task<RecognitionSession, any Error>?
        var active: RecognitionSession?
        var capturing = false
        var preRoll: [AnalyzerInput] = []
        var preRollFrames: AVAudioFrameCount = 0
        var trailingWait: CheckedContinuation<Void, Never>?
        var vocabulary: [String] = []
        var recording: [Float] = []
        var vocabularyPush: Task<Void, Never>?

        mutating func clearPreRoll() {
            preRoll.removeAll(keepingCapacity: true)
            preRollFrames = 0
        }
    }

    public init(
        locale: Locale = .current,
        keepMicrophoneOpen: Bool = true,
        onModelDownloadProgress: (@Sendable (Double) -> Void)? = nil
    ) {
        self.preferredLocale = locale
        self.keepMicrophoneOpen = keepMicrophoneOpen
        self.onModelDownloadProgress = onModelDownloadProgress
        (partials, partialsContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public func prepare() async throws {
        let model = try await prepareRecogniser()
        try await MicrophoneInput.requestAccess()
        let microphone = MicrophoneInput(target: model.format) { [weak self] audio in
            self?.ingest(audio)
        }
        state.withLock { $0.microphone = microphone }
        if keepMicrophoneOpen { try microphone.start() }
    }

    /// The names the next commands are likely to contain: open apps, window and tab titles, file
    /// and repo names, nicknames. Returns at once; the recogniser for the next command takes the
    /// list in the background, so a list that changes at key-down applies from the command after.
    public func setVocabulary(_ words: [String]) async {
        var seen = Set<String>()
        let unique = words.filter { !$0.isEmpty && seen.insert($0).inserted }
        let changed = state.withLock { state in
            guard state.vocabulary != unique else { return false }
            state.vocabulary = unique
            return true
        }
        if changed { pushVocabulary() }
    }

    public func start() async throws {
        let microphone = try state.withLock { state in
            guard let microphone = state.microphone else { throw SpeechError.notPrepared }
            if !keepMicrophoneOpen { state.clearPreRoll() }
            state.recording.removeAll(keepingCapacity: true)
            state.capturing = true
            return microphone
        }
        do {
            try microphone.start()
            let session = try await takeSession()
            let stillHeld = state.withLock { state in
                guard state.capturing else { return false }
                state.preRoll.forEach(session.append)
                state.preRoll.forEach { state.recording.append(contentsOf: Self.samples(in: $0.buffer)) }
                state.clearPreRoll()
                state.active = session
                return true
            }
            // finish() arrived while the recogniser was still being built: keep it for next time.
            if !stillHeld {
                state.withLock { $0.standby = Task { session } }
                pushVocabulary()
            }
        } catch {
            state.withLock { $0.capturing = false }
            throw error
        }
    }

    public func finish() async throws -> String {
        let capturing = state.withLock { state in
            if state.active == nil { state.capturing = false }
            return state.active != nil
        }
        guard capturing else { throw SpeechError.notStarted }
        await waitForTrailingAudio()
        let (session, microphone) = state.withLock { state in
            defer { state.active = nil }
            state.capturing = false
            return (state.active, state.microphone)
        }
        if !keepMicrophoneOpen { microphone?.stop() }
        guard let session else { throw SpeechError.notStarted }
        // Built after this command's text is out, so it never competes with finalising it.
        defer { refillStandby() }
        return try await session.finish()
    }

    /// macOS hands microphone audio over in 100 ms blocks whatever size is asked for, so at key
    /// release up to 100 ms of the last word has not arrived yet. Waiting for the next block
    /// keeps that word whole; the limit covers a microphone that has stopped delivering.
    private func waitForTrailingAudio() async {
        let limit = Task {
            try await Task.sleep(for: Self.trailingAudioLimit)
            resumeTrailingWait()
        }
        await withCheckedContinuation { continuation in
            state.withLock { $0.trailingWait = continuation }
        }
        limit.cancel()
    }

    private func resumeTrailingWait() {
        state.withLock { state in
            state.trailingWait?.resume()
            state.trailingWait = nil
        }
    }

    /// The audio of the command just finished, as mono samples, for a second engine to transcribe.
    func takeRecording() -> (samples: [Float], sampleRate: Double) {
        state.withLock { state in
            defer { state.recording.removeAll(keepingCapacity: true) }
            return (state.recording, state.model?.format.sampleRate ?? 0)
        }
    }

    private static func samples(in buffer: AVAudioPCMBuffer) -> [Float] {
        let count = Int(buffer.frameLength)
        if let floats = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: floats[0], count: count))
        }
        if let integers = buffer.int16ChannelData {
            return UnsafeBufferPointer(start: integers[0], count: count).map { Float($0) / Float(Int16.max) }
        }
        return []
    }

    /// The model and a ready recogniser, without touching the microphone.
    func prepareRecogniser() async throws -> SpeechModel {
        if let model = state.withLock({ $0.model }) { return model }
        let model = try await SpeechModel.load(preferred: preferredLocale, onDownloadProgress: onModelDownloadProgress)
        let standby = makeSession(model)
        state.withLock { state in
            state.model = model
            state.standby = standby
        }
        pushVocabulary()
        _ = try await standby.value
        return model
    }

    func takeSession() async throws -> RecognitionSession {
        let (standby, model) = state.withLock { state in
            defer { state.standby = nil }
            return (state.standby, state.model)
        }
        if let standby { return try await standby.value }
        guard let model else { throw SpeechError.notPrepared }
        return try await makeSession(model).value
    }

    func refillStandby() {
        let refilled = state.withLock { state in
            guard let model = state.model, state.standby == nil else { return false }
            state.standby = makeSession(model)
            return true
        }
        if refilled { pushVocabulary() }
    }

    /// Hands the current vocabulary to the waiting recogniser without making anyone wait for it.
    /// Pushes run one after another and each reads the list when it runs, so the last one always
    /// leaves the newest list in place.
    private func pushVocabulary() {
        state.withLock { state in
            guard let standby = state.standby else { return }
            let previous = state.vocabularyPush
            state.vocabularyPush = Task { [weak self] in
                await previous?.value
                guard let self, let session = try? await standby.value else { return }
                await session.setVocabulary(self.state.withLock { $0.vocabulary })
            }
        }
    }

    private func makeSession(_ model: SpeechModel) -> Task<RecognitionSession, any Error> {
        let continuation = partialsContinuation
        return Task { try await RecognitionSession(model: model) { continuation.yield($0) } }
    }

    private func ingest(_ audio: AnalyzerInput) {
        state.withLock { state in
            if let session = state.active {
                session.append(audio)
                state.recording.append(contentsOf: Self.samples(in: audio.buffer))
                state.trailingWait?.resume()
                state.trailingWait = nil
                return
            }
            state.preRoll.append(audio)
            state.preRollFrames += audio.buffer.frameLength
            // While start() waits for the recogniser nothing is dropped; otherwise keep only
            // the most recent stretch.
            guard !state.capturing, let rate = state.model?.format.sampleRate else { return }
            let limit = AVAudioFrameCount(rate * Self.preRollSeconds)
            while let oldest = state.preRoll.first, state.preRollFrames - oldest.buffer.frameLength >= limit {
                state.preRollFrames -= oldest.buffer.frameLength
                state.preRoll.removeFirst()
            }
        }
    }
}
