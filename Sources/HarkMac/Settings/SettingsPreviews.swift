import AppKit
import HarkCore
import SwiftUI

extension SettingsWindow {
    /// Renders every section to PNG files in `folder` with sample data, in light and dark, so the
    /// design can be reviewed without a screen: "<section>-light.png", "<section>-dark.png".
    public static func renderPreviews(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let appearances: [(name: String, appearance: NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        for section in SettingsSection.allCases {
            for (name, appearance) in appearances {
                let model = SettingsModel.sample()
                model.section = section
                let window = SettingsWindowController(model: model).window
                // Off screen the highlight of the chosen tab draws as a solid block that hides its label.
                window.toolbar?.selectedItemIdentifier = nil
                let png = try render(window, appearance: appearance)
                try png.write(to: folder.appending(path: "\(section.rawValue)-\(name).png"))
            }
        }
        // A sheet cannot be drawn off screen with the window it belongs to, so it gets its own image.
        for (name, appearance) in appearances {
            let sheet = StarterRoutinesSheet(
                routines: SettingsModel.sample().missingStarterRoutines, onAdd: { _ in }, onCancel: {})
            let window = NSWindow(contentViewController: NSHostingController(rootView: sheet))
            window.styleMask = [.borderless]
            let png = try render(window, appearance: appearance)
            try png.write(to: folder.appending(path: "starter-\(name).png"))
        }
        try renderMenuHeaders(to: folder, appearances: appearances)
        try renderKeyList(to: folder, appearances: appearances)
        try renderDictationPills(to: folder, appearances: appearances)
        // The Understanding tab at full height, since the window scrolls and the preview does not.
        for (name, appearance) in appearances {
            let host = NSHostingController(rootView: UnderstandingTab(model: SettingsModel.sample()).frame(width: 640, height: 1250))
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.borderless]
            try render(window, appearance: appearance).write(to: folder.appending(path: "model-tall-\(name).png"))
        }
    }

    /// The dictation pill in each of its states.
    private static func renderDictationPills(to folder: URL, appearances: [(name: String, appearance: NSAppearance.Name)]) throws {
        let states: [(DictationState, String)] = [
            (.listening, "listening"), (.typing, "typing"), (.typed(14), "typed"),
            (.error("A password field is selected, so Hark did not type."), "error"),
        ]
        for (state, label) in states {
            for (name, appearance) in appearances {
                let model = DictationModel()
                model.state = state
                let host = NSHostingView(rootView: DictationPill(model: model).padding(8).background(.background))
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                try render(window, appearance: appearance).write(to: folder.appending(path: "dictation-\(label)-\(name).png"))
            }
        }
    }

    /// The open list of a key picker, with sample rows: a chosen key, tags, a key in use and the reset group.
    private static func renderKeyList(to folder: URL, appearances: [(name: String, appearance: NSAppearance.Name)]) throws {
        let options: [SelectOption<String>] = [
            SelectOption(value: "fn", title: "fn (Globe)", symbol: "globe"),
            SelectOption(value: "leftControl", title: "Left Control", symbol: "control"),
            SelectOption(value: "leftOption", title: "Left Option", symbol: "option"),
            SelectOption(value: "leftCommand", title: "Left Command", symbol: "command"),
            SelectOption(value: "rightOption", title: "Right Option", symbol: "option", trailingSymbol: "star.fill"),
            SelectOption(value: "rightCommand", title: "Right Command", symbol: "command", unavailable: "In use"),
            SelectOption(value: "rightShift", title: "Right Shift", symbol: "shift"),
            SelectOption(value: "f13", title: "F13", symbol: "keyboard"),
            SelectOption(value: "", title: "Off", symbol: "nosign", separatorBefore: true),
            SelectOption(value: "@reset", title: "Reset to default", symbol: "arrow.counterclockwise"),
        ]
        let field = SelectField(
            label: "Key to hold", options: options, summary: "Right Option", helper: nil, problem: nil,
            closesOnChoice: true, isSelected: { $0 == "rightOption" }, choose: { _ in })
        for (name, appearance) in appearances {
            let window = NSWindow(contentViewController: NSHostingController(rootView: field.list.frame(height: 400).background(.background)))
            window.styleMask = [.borderless]
            try render(window, appearance: appearance).write(to: folder.appending(path: "keylist-\(name).png"))
        }
    }

    /// The card at the top of the menu bar menu, ready and waiting for a permission.
    private static func renderMenuHeaders(to folder: URL, appearances: [(name: String, appearance: NSAppearance.Name)]) throws {
        let ready = MenuHeaderState()
        ready.status = "Hold right Option to speak, tap right Command to type"
        ready.lastCommand = "Open Chrome and search Jantar Mantar in new tab."
        let waiting = MenuHeaderState()
        waiting.status = "Turn on Accessibility for Hark\u{2026}"
        waiting.action = {}
        for (state, label) in [(ready, "ready"), (waiting, "waiting")] {
            for (name, appearance) in appearances {
                let window = NSWindow(contentViewController: NSHostingController(rootView: MenuHeaderView(state: state)))
                window.styleMask = [.borderless]
                try render(window, appearance: appearance).write(to: folder.appending(path: "menu-\(label)-\(name).png"))
            }
        }
    }

    /// `ImageRenderer` draws a grouped form and its controls as an empty rectangle, so the real
    /// window is drawn into a bitmap instead. It is never put on screen.
    private static func render(_ window: NSWindow, appearance: NSAppearance.Name) throws -> Data {
        window.appearance = NSAppearance(named: appearance)
        window.layoutIfNeeded()
        // The form lays out its rows over a few turns of the run loop.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

        let scale = 2
        guard let frame = window.contentView?.superview,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(frame.bounds.width) * scale,
                pixelsHigh: Int(frame.bounds.height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = frame.bounds.size
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }
}

extension SettingsModel {
    fileprivate static func sample() -> SettingsModel {
        let config = Config(
            searchFolders: ["~/Projects", "~/Documents/Work"],
            repos: ["~/Projects/shop-backend", "~/Projects/shop-website"],
            aliases: ["the backend": "shop-backend", "the website": "shop-website", "my notes": "meeting-notes"],
            routines: [
                Routine(name: "start my day", steps: [Step(say: "open the projects folder in VS Code")]),
                Routine(name: "stop port", steps: [Step(shell: "lsof -ti :{arg} | xargs kill", destructive: true)]),
                Routine(name: "pull all", steps: [Step(shell: "git -C {repo} pull --ff-only", timeout: 60)]),
            ],
            links: ["the task board": "https://tracker.example.com/board"],
            model: "careful-model",
            modelURL: "https://models.example.com/v1",
            modelKey: "sample-key-not-real"
        )
        let history = sampleHistory
        let scratch = FileManager.default.temporaryDirectory.appending(path: "hark-preview-learning")
        let system = SettingsSystem(
            permissionStatus: { $0 == .automation ? .notAsked : .granted },
            openPermissionSettings: { _ in },
            loginItemIsOn: { true },
            setLoginItem: { _ in },
            history: { history },
            reports: { [] },
            report: { _ in },
            listModels: { _, _ in ["careful-model", "fast-model"] },
            learning: LearningCenter(
                activity: ActivityLog(url: scratch.appending(path: "activity.jsonl")),
                history: TimingLog(url: scratch.appending(path: "timings.jsonl")),
                store: LearningStore(url: scratch.appending(path: "learning.json")))
        )
        let model = SettingsModel(config: config, system: system, onChange: { _ in })
        model.refreshLoginItem()
        model.permissionStatuses = Dictionary(
            uniqueKeysWithValues: Permission.allCases.map { ($0, system.permissionStatus($0)) })
        model.history = history.reversed()
        model.modelLookup = .found(["careful-model", "fast-model", "quick-model"])
        model.learned = LearningSnapshot(
            suggestions: [
                Suggestion(
                    id: "n", kind: .name, title: "When you say \u{201C}open slak\u{201D}, hear \u{201C}open slack\u{201D}",
                    detail: "Hark missed it 2 times, then you said it the other way and it worked."),
                Suggestion(
                    id: "p", kind: .page, title: "Open \u{201C}github\u{201D} by name",
                    detail: "You were on github.com on 5 different days."),
                Suggestion(
                    id: "r", kind: .routine, title: "Start your day with one word: \u{201C}morning\u{201D}",
                    detail: "You opened these together at the start of 4 days: Linear, Slack, github.com."),
            ],
            deadEnds: [DeadEnd(phrase: "search for swift concurrency", count: 3, lastSeen: Date(), topic: "Searching the web")],
            accepted: [
                LearningState.Accepted(id: "a", kind: .page, title: "Open \u{201C}linear\u{201D} by name", at: Date()),
            ])
        model.setAddress("models.example.com/v1", for: .online)
        if let stopPort = model.routines.dropFirst().first {
            model.selectRoutine(stopPort.id)
            model.editRoutine(stopPort.id) { $0.name = "delete port" }
        }
        let unsafeLink = model.addLink()
        if let index = model.links.firstIndex(where: { $0.id == unsafeLink }) {
            model.links[index].said = "the design files"
            model.links[index].meant = "ftp://files.example.com/designs"
        }
        model.finishEditingLink(unsafeLink)
        let notUnderstood = history[4]
        model.showReports([
            WrongLog.Entry(
                at: notUnderstood.at, heard: notUnderstood.raw, did: "Not understood", wanted: "make the window bigger")
        ])
        model.reportingRow = ReportKey(history[6])
        return model
    }

    private static var sampleHistory: [Timings] {
        let rows: [(minutesAgo: Double, raw: String, outcome: String, summary: String?, seconds: Double)] = [
            (2880, "open the shop website project in VS Code", "done", "Opened shop-website in Visual Studio Code", 1.1),
            (1440, "switch to the pricing tab", "done", "Switched to Pricing in Google Chrome", 0.4),
            (300, "close this window", "confirm", "Asked before closing the Notes window", 0.6),
            (185, "open the report", "choose", "Found 3 files called report", 0.9),
            (64, "make it purple", "notUnderstood", "Hark did not know what to change", 2.1),
            (22, "open the backend project", "done", "Opened shop-backend in Finder", 0.8),
            (5, "switch to the design tab", "failed", "Google Chrome did not answer", 3.4),
            (1, "paste the address I copied", "done", "Pasted into Mail", 0.3),
        ]
        return rows.map { row in
            var entry = Timings(
                at: Date(timeIntervalSinceNow: -row.minutesAgo * 60), raw: row.raw, verb: nil, outcome: row.outcome,
                transcribeMs: 0, parseMs: 0, matchMs: 0, actMs: 0, totalMs: row.seconds * 1000)
            entry.summary = row.summary
            return entry
        }
    }
}
