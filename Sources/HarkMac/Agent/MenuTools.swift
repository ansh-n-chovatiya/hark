import AppKit
import ApplicationServices
import HarkCore

private struct MenuToolError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

public struct ListMenuTool: Tool {
    public init() {}

    public var spec: ToolSpec {
        ToolSpec(
            name: "list_menu",
            description: "List the menus of a running app, with the items in each menu. Use it to find the exact "
                + "menu item before click_menu.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "app": .object(["type": .string("string"), "description": .string("Name of a running app")]),
                ]),
                "required": .array([.string("app")]),
            ]),
            kind: .lookup)
    }

    public func describe(_ arguments: JSONValue) -> String {
        "List the menus of \(arguments["app"]?.string ?? "an app")"
    }

    public func call(_ arguments: JSONValue) async throws -> ToolResult {
        let name = try MenuArguments.app(arguments)
        let app = try await MenuToolApps.running(named: name)
        let lines = try AppMenuBar.lines(of: app.processIdentifier, appName: name)
        return ToolResult(output: lines.joined(separator: "\n"))
    }
}

public struct ClickMenuTool: Tool {
    public init() {}

    public var spec: ToolSpec {
        ToolSpec(
            name: "click_menu",
            description: "Choose an item from a running app's menu bar, for example path [\"File\", \"New Window\"]. "
                + "Use list_menu first when unsure of the exact titles.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "app": .object(["type": .string("string"), "description": .string("Name of a running app")]),
                    "path": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Titles from the top-level menu down to the item"),
                    ]),
                ]),
                "required": .array([.string("app"), .string("path")]),
            ]),
            kind: .action)
    }

    public func describe(_ arguments: JSONValue) -> String {
        let path = MenuArguments.titles(arguments).joined(separator: " > ")
        return "Choose \(path) in \(arguments["app"]?.string ?? "an app")"
    }

    public func kind(for arguments: JSONValue) -> ToolKind {
        let titles = MenuArguments.titles(arguments)
        return Self.closesOrQuits(titles) || MenuAsk.needsYes(titles) ? .destructive : .action
    }

    /// The item closes or quits something. Hark's own rules for those ask first and are not bypassed by a menu.
    static func closesOrQuits(_ path: [String]) -> Bool {
        let text = path.joined(separator: " > ").lowercased()
        return MenuSafety.destructiveMenuWords.contains(where: text.contains)
    }

    public func call(_ arguments: JSONValue) async throws -> ToolResult {
        let name = try MenuArguments.app(arguments)
        let path = MenuArguments.titles(arguments)
        guard path.count >= 2 else {
            throw MenuToolError(message: "Give the menu and the item, for example File > New Window.")
        }
        if let word = path.lazy.compactMap(MenuSafety.deletionWord).first {
            throw MenuToolError(message: "Hark does not choose menu items about \"\(word)\".")
        }
        let app = try await MenuToolApps.running(named: name)
        try await MenuToolApps.bringForward(app)
        try AppMenuBar.choose(path, in: app.processIdentifier, appName: name)
        return ToolResult(output: "Chose \(path.joined(separator: " > ")) in \(name).",
                          summary: "Chose \(path.joined(separator: " > ")) in \(name)")
    }
}

public struct PressKeysTool: Tool {
    public init() {}

    public var spec: ToolSpec {
        ToolSpec(
            name: "press_keys",
            description: "Press a keyboard shortcut such as cmd+shift+n in a running app, or in the front app when "
                + "no app is given. Keys: letters, digits, f1 to f12, up, down, left, right, return, tab, space, "
                + "escape, with cmd, shift, option and control. Prefer click_menu when a menu item exists.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "keys": .object(["type": .string("string"), "description": .string("For example cmd+shift+n")]),
                    "app": .object(["type": .string("string"), "description": .string("Name of a running app")]),
                ]),
                "required": .array([.string("keys")]),
            ]),
            kind: .action)
    }

    public func describe(_ arguments: JSONValue) -> String {
        let keys = arguments["keys"]?.string ?? "keys"
        guard let app = arguments["app"]?.string, !app.isEmpty else { return "Press \(keys)" }
        return "Press \(keys) in \(app)"
    }

    public func kind(for arguments: JSONValue) -> ToolKind {
        guard let text = arguments["keys"]?.string, let shortcut = try? KeyShortcut(parsing: text) else { return .action }
        return shortcut.isDestructive ? .destructive : .action
    }

    public func call(_ arguments: JSONValue) async throws -> ToolResult {
        guard let text = arguments["keys"]?.string, !text.isEmpty else {
            throw MenuToolError(message: "No keys were given.")
        }
        let shortcut = try KeyShortcut(parsing: text)
        // Plain keys spell words, and words sent to a terminal are commands. A shortcut needs
        // Command, Control or Option; without one only keys that cannot spell anything pass.
        let isShortcut = !shortcut.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate])
        guard isShortcut || KeySafety.harmlessAlone.contains(shortcut.key) else {
            throw MenuToolError(message: "Hark presses shortcuts, not plain keys: it does not type.")
        }
        let appName = arguments["app"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        let target: NSRunningApplication
        if let appName {
            target = try await MenuToolApps.running(named: appName)
        } else {
            guard let front = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication }) else {
                throw MenuToolError(message: "No app is in front.")
            }
            target = front
        }
        guard !KeySafety.isTerminal(target) else {
            throw MenuToolError(message: "Hark does not send keys to a terminal.")
        }
        if appName != nil { try await MenuToolApps.bringForward(target) }
        try shortcut.send(to: target.processIdentifier)
        let place = appName.map { " in \($0)" } ?? ""
        return ToolResult(output: "Pressed \(shortcut.text)\(place).", summary: "Pressed \(shortcut.text)\(place)")
    }
}

private enum MenuArguments {
    static func app(_ arguments: JSONValue) throws -> String {
        guard let name = arguments["app"]?.string, !name.isEmpty else {
            throw MenuToolError(message: "No app was named.")
        }
        return name
    }

    static func titles(_ arguments: JSONValue) -> [String] {
        arguments["path"]?.array?.compactMap(\.string) ?? []
    }
}

enum MenuSafety {
    private static let deletionStems = [
        "delet", "trash", "erase", "remov", "uninstall", "discard", "clear", "empty", "reset", "revert",
    ]
    private static let deletionWords = ["bin", "bins"]

    static let destructiveMenuWords = [
        "close", "quit", "exit", "log out", "sign out", "shut down", "restart",
    ]

    /// The word in a title that makes it about deleting, if any.
    static func deletionWord(in title: String) -> String? {
        let words = title.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.first { word in
            deletionWords.contains(word) || deletionStems.contains(where: word.hasPrefix)
        }
    }
}

enum MenuToolApps {
    private static let aliases = ["vs code": "code", "vscode": "code", "visual studio code": "code"]

    @MainActor static func running(named name: String) throws -> NSRunningApplication {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        let target = aliases[wanted] ?? wanted
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.localizedName != nil
        }
        let exact = apps.first { $0.localizedName?.lowercased() == target }
        let partial = apps.filter { $0.localizedName?.lowercased().contains(target) == true }
        if let found = exact ?? (partial.count == 1 ? partial.first : nil) { return found }
        throw MenuToolError(message: "\"\(name)\" is not running.")
    }

    @MainActor static func bringForward(_ app: NSRunningApplication) async throws {
        let pid = app.processIdentifier
        if await isFront(pid, waiting: 0) { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 2)
        AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if await isFront(pid, waiting: 1) { return }
        if let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        guard await isFront(pid, waiting: 2) else {
            throw MenuToolError(message: "Could not bring \(app.localizedName ?? "the app") to the front.")
        }
    }

    @MainActor private static func isFront(_ pid: pid_t, waiting seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            if Date() >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }
}

enum AppMenuBar {
    private static let timeout: Float = 2
    private static let lineLimit = 200

    static func lines(of pid: pid_t, appName: String) throws -> [String] {
        let tops = try topMenus(of: pid, appName: appName)
        var lines: [String] = []
        for top in tops where isUsable(top) {
            lines.append(title(of: top))
            for item in submenu(of: top) where isUsable(item) {
                lines.append("  " + title(of: item))
                for inner in submenu(of: item) where isUsable(inner) {
                    lines.append("    " + title(of: inner))
                }
            }
        }
        if lines.count > lineLimit {
            return Array(lines.prefix(lineLimit)) + ["(list cut at \(lineLimit) lines)"]
        }
        return lines
    }

    struct Entry {
        let path: [String]
        let enabled: Bool
    }

    /// Every item, greyed out or not, with the menus it sits under, down to submenus one level deep.
    /// Greyed-out ones are kept so a request for one of them can say so, instead of quietly doing a
    /// different thing.
    static func entries(of pid: pid_t, appName: String) throws -> [Entry] {
        var found: [Entry] = []
        for top in try topMenus(of: pid, appName: appName) where !title(of: top).isEmpty {
            let topTitle = title(of: top)
            for item in submenu(of: top) where !title(of: item).isEmpty {
                found.append(Entry(path: [topTitle, title(of: item)], enabled: enabled(item)))
                for inner in submenu(of: item) where !title(of: inner).isEmpty {
                    found.append(Entry(path: [topTitle, title(of: item), title(of: inner)], enabled: enabled(inner)))
                }
            }
        }
        return found
    }

    static func choose(_ path: [String], in pid: pid_t, appName: String) throws {
        var level = try topMenus(of: pid, appName: appName)
        var trail = appName
        for (index, part) in path.enumerated() {
            let wanted = normalised(part)
            guard let match = level.first(where: { normalised(title(of: $0)) == wanted }) else {
                throw MenuToolError(message: "No menu item \"\(part)\" in \(trail).")
            }
            if index < path.count - 1 {
                level = submenu(of: match)
                trail = "\(part) in \(appName)"
                continue
            }
            guard enabled(match) else { throw MenuToolError(message: "\"\(part)\" is greyed out in \(trail).") }
            AXUIElementSetMessagingTimeout(match, timeout)
            guard AXUIElementPerformAction(match, kAXPressAction as CFString) == .success else {
                throw MenuToolError(message: "\(appName) did not accept \"\(part)\".")
            }
        }
    }

    private static func topMenus(of pid: pid_t, appName: String) throws -> [AXUIElement] {
        guard AXIsProcessTrusted() else {
            throw MenuToolError(message: "Hark needs the Accessibility permission to read menus.")
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let bar = attribute(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else {
            throw MenuToolError(message: "\(appName) has no menu bar to read.")
        }
        // The first entry is the Apple menu.
        return Array(children(of: bar as! AXUIElement).dropFirst())
    }

    private static func submenu(of element: AXUIElement) -> [AXUIElement] {
        let menu = children(of: element).first { attribute($0, kAXRoleAttribute) as? String == kAXMenuRole }
        return menu.map(children(of:)) ?? []
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(element, timeout)
        return attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func isUsable(_ element: AXUIElement) -> Bool {
        !title(of: element).isEmpty && enabled(element)
    }

    private static func title(of element: AXUIElement) -> String {
        attribute(element, kAXTitleAttribute) as? String ?? ""
    }

    private static func enabled(_ element: AXUIElement) -> Bool {
        attribute(element, kAXEnabledAttribute) as? Bool ?? true
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func normalised(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespaces).lowercased()
        for ending in ["…", "..."] where text.hasSuffix(ending) {
            text = String(text.dropLast(ending.count)).trimmingCharacters(in: .whitespaces)
        }
        return text
    }
}

/// What an app's menu bar offers, for choosing an item by the words the user said.
enum AppMenus {
    static func entries(of pid: pid_t, appName: String) throws -> [AppMenuBar.Entry] {
        try AppMenuBar.entries(of: pid, appName: appName)
    }
}

/// Keys are the widest door a model has into the Mac, so they are fenced: no typing, and
/// nothing at all into an app where text becomes a command (decision 0008).
enum KeySafety {
    static let harmlessAlone: Set<String> = [
        "left", "right", "up", "down", "escape", "esc", "tab", "space",
        "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
    ]

    private static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp",
        "net.kovidgoyal.kitty", "org.alacritty", "com.mitchellh.ghostty", "com.github.wez.wezterm",
        "co.zeit.hyper", "org.tabby",
    ]

    static func isTerminal(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return terminals.contains(id)
    }
}

private struct KeyShortcut {
    private static let modifierNames: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "shift": .maskShift,
        "option": .maskAlternate, "opt": .maskAlternate, "alt": .maskAlternate,
        "control": .maskControl, "ctrl": .maskControl,
    ]
    private static let deleteKeys: Set<String> = ["delete", "del", "backspace", "forwarddelete", "fwddelete"]
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "escape": 53, "esc": 53,
    ]
    private static let destructiveCombos: Set<String> = [
        "cmd+w", "cmd+shift+w", "cmd+q", "cmd+option+q",
    ]

    let key: String
    let code: CGKeyCode
    let flags: CGEventFlags
    private let modifiers: [String]

    init(parsing text: String) throws {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, !key.isEmpty else {
            throw MenuToolError(message: "\"\(text)\" is not a key combination.")
        }
        if parts.contains(where: Self.deleteKeys.contains) {
            throw MenuToolError(message: "Hark does not press the delete key.")
        }
        guard let code = Self.keyCodes[key] else {
            throw MenuToolError(message: "Hark does not know the key \"\(key)\".")
        }
        var flags: CGEventFlags = []
        var names: [String] = []
        for part in parts.dropLast() {
            guard let flag = Self.modifierNames[part] else {
                throw MenuToolError(message: "Hark does not know the modifier \"\(part)\".")
            }
            flags.insert(flag)
            names.append(Self.canonical(flag))
        }
        self.key = key
        self.code = code
        self.flags = flags
        self.modifiers = Self.order.filter(names.contains)
    }

    private static let order = ["cmd", "shift", "option", "control"]

    private static func canonical(_ flag: CGEventFlags) -> String {
        switch flag {
        case .maskCommand: "cmd"
        case .maskShift: "shift"
        case .maskAlternate: "option"
        default: "control"
        }
    }

    var text: String { (modifiers + [key]).joined(separator: "+") }

    var isDestructive: Bool { Self.destructiveCombos.contains(text) }

    func send(to pid: pid_t) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
            throw MenuToolError(message: "Could not create the key press.")
        }
        for event in [down, up] {
            event.flags = flags
            event.postToPid(pid)
        }
    }
}
