import AppKit
import SwiftUI

@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    let window: NSWindow
    private let model: SettingsModel
    private var ownsMainMenu = false

    init(model: SettingsModel) {
        self.model = model
        window = NSWindow(contentViewController: NSHostingController(rootView: SettingsContent(model: model)))
        super.init()
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        let toolbar = NSToolbar(identifier: "dev.hark.settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
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
        window.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(section.rawValue)
    }

    @objc func selectFromToolbar(_ sender: NSToolbarItem) {
        guard let section = SettingsSection(rawValue: sender.itemIdentifier.rawValue) else { return }
        select(section)
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

    // MARK: NSToolbarDelegate

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let section = SettingsSection(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = section.title
        item.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil)
        item.target = self
        item.action = #selector(selectFromToolbar(_:))
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        sectionIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        sectionIdentifiers
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        sectionIdentifiers
    }

    private var sectionIdentifiers: [NSToolbarItem.Identifier] {
        SettingsSection.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }
}
