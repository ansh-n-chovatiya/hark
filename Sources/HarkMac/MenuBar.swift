import AppKit
import SwiftUI

@MainActor public final class MenuBar: NSObject, NSMenuDelegate {
    public var onSettings: (() -> Void)? {
        didSet {
            settingsItem.isHidden = onSettings == nil
            settingsSeparator.isHidden = onSettings == nil
        }
    }

    /// Opens the bar for typing a command.
    public var onTypeCommand: (() -> Void)?

    /// Opens what Hark has noticed.
    public var onLearning: (() -> Void)?
    /// "What can I say?", "History…", "Check for updates…", and pausing: true to pause, false to resume.
    public var onHelp: (() -> Void)?
    public var onHistory: (() -> Void)?
    public var onUpdates: (() -> Void)?
    public var onPause: ((Bool) -> Void)?
    private var paused = false
    private var readyStatus: (text: String, detail: String?)?
    private let pauseItem = NSMenuItem(title: "Pause Hark", action: #selector(togglePause), keyEquivalent: "")

    private static let lastCommandLimit = 60

    private let statusItem: NSStatusItem
    private let header = MenuHeaderState()
    private let headerView: NSHostingView<MenuHeaderView>
    private let headerItem = NSMenuItem()
    private let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    private let settingsSeparator = NSMenuItem.separator()
    private var lastDictation: String?
    private let dictationItem = NSMenuItem(title: "Copy last dictation", action: #selector(copyLastDictation), keyEquivalent: "")
    private let learningItem = NSMenuItem(title: "", action: #selector(openLearning), keyEquivalent: "")

    public override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        headerView = NSHostingView(rootView: MenuHeaderView(state: header))
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Hark")

        let menu = NSMenu()
        menu.delegate = self
        headerItem.view = headerView
        menu.addItem(headerItem)
        menu.addItem(.separator())

        let type = NSMenuItem(title: "Type a command…", action: #selector(typeCommand), keyEquivalent: "")
        type.target = self
        type.image = Self.icon("keyboard")
        menu.addItem(type)
        dictationItem.target = self
        dictationItem.image = Self.icon("doc.on.clipboard")
        dictationItem.isHidden = true
        let help = NSMenuItem(title: "What can I say?", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        help.image = Self.icon("questionmark.bubble")
        menu.addItem(help)
        let history = NSMenuItem(title: "History…", action: #selector(showHistory), keyEquivalent: "")
        history.target = self
        history.image = Self.icon("clock.arrow.circlepath")
        menu.addItem(history)
        menu.addItem(dictationItem)
        learningItem.target = self
        learningItem.image = Self.icon("lightbulb")
        learningItem.isHidden = true
        menu.addItem(learningItem)
        menu.addItem(.separator())

        // Hidden until something handles it, so the menu never offers an entry that does nothing.
        pauseItem.target = self
        pauseItem.image = Self.icon("pause.circle")
        menu.addItem(pauseItem)
        let updates = NSMenuItem(title: "Check for updates…", action: #selector(checkUpdates), keyEquivalent: "")
        updates.target = self
        updates.image = Self.icon("arrow.down.circle")
        menu.addItem(updates)
        menu.addItem(.separator())
        settingsItem.target = self
        settingsItem.image = Self.icon("gearshape")
        settingsItem.isHidden = true
        settingsSeparator.isHidden = true
        menu.addItem(settingsItem)
        menu.addItem(settingsSeparator)

        let quit = NSMenuItem(title: "Quit Hark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = Self.icon("power")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private static func icon(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    /// The card's height depends on its text, so it is measured each time the menu opens.
    public func menuWillOpen(_ menu: NSMenu) {
        headerView.setFrameSize(NSSize(width: MenuHeaderView.width, height: headerView.fittingSize.height))
    }

    /// The first line of the menu: how to use Hark, or what it is waiting for. With an action the
    /// line can be clicked, for example to open the settings pane it names.
    public func setStatus(_ text: String, detail: String? = nil, action: (() -> Void)? = nil) {
        if action == nil { readyStatus = (text, detail) }
        guard !paused else { return }
        header.status = text
        header.detail = detail
        header.action = action.map { run in { [weak self] in
            self?.statusItem.menu?.cancelTracking()
            run()
        } }
    }

    public func setLastCommand(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        header.lastCommand = trimmed.count > Self.lastCommandLimit
            ? trimmed.prefix(Self.lastCommandLimit) + "…"
            : trimmed
    }

    /// "Hark noticed 2 things", shown only when there is something to look at.
    public func setSuggestionCount(_ count: Int) {
        learningItem.isHidden = count == 0
        learningItem.title = count == 1 ? "Hark noticed 1 thing\u{2026}" : "Hark noticed \(count) things\u{2026}"
    }

    /// Keeps the last dictated words in memory only, so they can be copied if they went to the wrong place.
    public func setLastDictation(_ text: String) {
        lastDictation = text
        dictationItem.isHidden = false
    }

    @objc private func copyLastDictation() {
        guard let lastDictation else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastDictation, forType: .string)
    }

    @objc private func togglePause() {
        paused.toggle()
        pauseItem.title = paused ? "Resume Hark" : "Pause Hark"
        pauseItem.image = Self.icon(paused ? "play.circle" : "pause.circle")
        if paused {
            header.status = "Paused"
            header.detail = "Hark is not listening. Choose Resume Hark in this menu."
            header.action = nil
        } else if let readyStatus {
            header.status = readyStatus.text
            header.detail = readyStatus.detail
        }
        onPause?(paused)
    }

    @objc private func showHelp() { onHelp?() }
    @objc private func showHistory() { onHistory?() }
    @objc private func checkUpdates() { onUpdates?() }

    @objc private func openLearning() {
        onLearning?()
    }

    @objc private func typeCommand() {
        onTypeCommand?()
    }

    @objc private func openSettings() {
        onSettings?()
    }

}
