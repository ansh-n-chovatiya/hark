import AppKit
import SwiftUI

@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let model: SettingsModel
    private var ownsMainMenu = false

    init(model: SettingsModel) {
        self.model = model
        window = NSWindow(contentViewController: NSHostingController(rootView: SettingsContent(model: model)))
        super.init()
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        // The sidebar and its colour run up under the title bar; the title stays for VoiceOver.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.delegate = self
        select(model.section)
        window.center()
    }

    func present(_ section: SettingsSection) {
        select(section)
        // A menu-bar-only app cannot own a key window or appear in the app switcher.
        NSApp.setActivationPolicy(.regular)
        if NSApp.mainMenu == nil {
            // Copy, paste and Close are menu shortcuts, so text boxes need a menu to exist.
            NSApp.mainMenu = SettingsMenu.make(target: self)
            ownsMainMenu = true
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func select(_ section: SettingsSection) {
        model.section = section
        window.title = section.title
    }

    @objc func selectFromMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let section = SettingsSection(rawValue: name) else { return }
        select(section)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Ends editing so a text box that still has the cursor hands over what was typed.
        window.makeFirstResponder(nil)
        if ownsMainMenu {
            NSApp.mainMenu = nil
            ownsMainMenu = false
        }
        NSApp.setActivationPolicy(.accessory)
    }
}
