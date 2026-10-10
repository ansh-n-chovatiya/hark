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

    private static let lastCommandLimit = 60

    private let statusItem: NSStatusItem
    private let header = MenuHeaderState()
    private let headerView: NSHostingView<MenuHeaderView>
    private let headerItem = NSMenuItem()
    private let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    private let settingsSeparator = NSMenuItem.separator()
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
        learningItem.target = self
        learningItem.image = Self.icon("lightbulb")
        learningItem.isHidden = true
        menu.addItem(learningItem)
        menu.addItem(.separator())

        // Hidden until something handles it, so the menu never offers an entry that does nothing.
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
    public func setStatus(_ text: String, action: (() -> Void)? = nil) {
        header.status = text
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
