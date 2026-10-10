import AppKit

@MainActor public final class MenuBar: NSObject {
    public var onSettings: (() -> Void)? {
        didSet {
            settingsItem.isHidden = onSettings == nil
            settingsSeparator.isHidden = onSettings == nil
        }
    }

    /// Opens the bar for typing a command.
    public var onTypeCommand: (() -> Void)?

    private static let lastCommandLimit = 60

    private let statusItem: NSStatusItem
    private let statusLine = NSMenuItem(title: "Getting ready", action: nil, keyEquivalent: "")
    private let lastCommandItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    private let settingsSeparator = NSMenuItem.separator()
    private var statusAction: (() -> Void)?

    public override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Hark")

        let menu = NSMenu()
        menu.addItem(statusLine)
        lastCommandItem.isHidden = true
        menu.addItem(lastCommandItem)
        menu.addItem(.separator())

        let type = NSMenuItem(title: "Type a command…", action: #selector(typeCommand), keyEquivalent: "")
        type.target = self
        menu.addItem(type)
        menu.addItem(.separator())

        // Hidden until something handles it, so the menu never offers an entry that does nothing.
        settingsItem.target = self
        settingsItem.isHidden = true
        settingsSeparator.isHidden = true
        menu.addItem(settingsItem)
        menu.addItem(settingsSeparator)

        menu.addItem(withTitle: "Quit Hark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// The first line of the menu: how to use Hark, or what it is waiting for. With an action the
    /// line can be clicked, for example to open the settings pane it names.
    public func setStatus(_ text: String, action: (() -> Void)? = nil) {
        statusLine.title = text
        statusAction = action
        statusLine.target = action == nil ? nil : self
        statusLine.action = action == nil ? nil : #selector(runStatusAction)
    }

    public func setLastCommand(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let shown = trimmed.count > Self.lastCommandLimit
            ? trimmed.prefix(Self.lastCommandLimit) + "…"
            : Substring(trimmed)
        lastCommandItem.title = "Last command: \(shown)"
        lastCommandItem.isHidden = false
    }

    @objc private func typeCommand() {
        onTypeCommand?()
    }

    @objc private func openSettings() {
        onSettings?()
    }

    @objc private func runStatusAction() {
        statusAction?()
    }
}
