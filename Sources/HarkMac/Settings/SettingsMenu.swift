import AppKit

/// The menu bar shown while the settings window is open. Hark has no menu bar of its own, and
/// without one the usual shortcuts for copy, paste and closing the window do nothing.
@MainActor enum SettingsMenu {
    static func make(target: SettingsWindowController) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("Hark", [
            item("Quit Hark", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        main.addItem(submenu("View", SettingsSection.allCases.enumerated().map { index, section in
            let entry = item(section.title, #selector(SettingsWindowController.selectFromMenu(_:)), "\(index + 1)")
            entry.target = target
            entry.representedObject = section.rawValue
            return entry
        }))
        main.addItem(submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        return main
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        menu.items = items
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    private static func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }
}
