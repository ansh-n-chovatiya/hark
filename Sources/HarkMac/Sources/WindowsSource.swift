import AppKit
import ApplicationServices
import HarkCore

public actor WindowsSource: ItemSource {
    public nonisolated let kinds: Set<ItemKind> = [.window]

    private var snapshot: [Item] = []
    private var elements: [String: Element] = [:]

    public init() {}

    public func refresh() async {
        guard AXIsProcessTrusted() else {
            snapshot = []
            elements = [:]
            return
        }
        let apps = await Self.runningApps()
        let found = await withTaskGroup(of: [FoundWindow].self) { group in
            for app in apps {
                group.addTask { Self.windows(of: app) }
            }
            var all: [FoundWindow] = []
            for await windows in group {
                all += windows
            }
            return all
        }
        let ordered = found.sorted { ($0.item.owner, $0.item.id) < ($1.item.owner, $1.item.id) }
        snapshot = ordered.map(\.item)
        elements = Dictionary(uniqueKeysWithValues: ordered.map { ($0.item.id, $0.element) })
    }

    public func items(for command: Command) async -> [Item] {
        snapshot
    }

    public func perform(_ verb: Verb, on item: Item) async throws -> UndoStep? {
        guard let pid = Self.pid(of: item) else { throw SourceError.gone(item.title) }
        switch verb {
        case .open:
            guard let window = elements[item.id] else { throw SourceError.gone(item.title) }
            let previous = await Self.frontmost()
            guard Self.focus(window, in: pid) else { throw SourceError.gone(item.title) }
            guard let previous else { return nil }
            return UndoStep(summary: "Went back from \(item.title)") {
                _ = Self.focus(previous.window, in: previous.pid)
            }
        case .hide:
            guard let app = NSRunningApplication(processIdentifier: pid) else {
                throw SourceError.gone(item.title)
            }
            app.hide()
            return UndoStep(summary: "Showed \(item.owner) again") { app.unhide() }
        case .close:
            guard let window = elements[item.id], Self.close(window.ref) else { throw SourceError.gone(item.title) }
            // A closed window cannot be brought back from outside its app, so there is no undo.
            return nil
        default:
            throw SourceError.unsupported(verb, item.kind)
        }
    }
}

// AXUIElement is an immutable handle to another process; every call on it is a message to that
// process, so sharing it across tasks is safe even though the type is not marked Sendable.
private struct Element: @unchecked Sendable {
    let ref: AXUIElement
}

private struct RunningApp: Sendable {
    let pid: pid_t
    let name: String
    let isFrontmost: Bool
}

private struct FoundWindow: Sendable {
    let item: Item
    let element: Element
}

private struct WindowFacts {
    var title = ""
    var subrole = ""
    var isMinimised = false
    var isMain = false
    var position = CGPoint.zero
    var size = CGSize.zero
}

extension WindowsSource {
    // An app that is busy or hung would otherwise hold a refresh for the six second system default.
    private static let answerTimeout: Float = 0.15
    // Restoring a minimised window answers only after its animation, well past answerTimeout.
    private static let actionTimeout: Float = 2
    private static let windowSubroles: Set<String> = [kAXStandardWindowSubrole, kAXDialogSubrole]
    private static let factNames = [
        kAXTitleAttribute, kAXSubroleAttribute, kAXMinimizedAttribute, kAXMainAttribute,
        kAXPositionAttribute, kAXSizeAttribute,
    ]

    @MainActor private static func runningApps() -> [RunningApp] {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let name = app.localizedName else { return nil }
            return RunningApp(pid: app.processIdentifier, name: name,
                              isFrontmost: app.processIdentifier == front)
        }
    }

    private static func windows(of app: RunningApp) -> [FoundWindow] {
        let appElement = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(appElement, answerTimeout)
        guard let windows = value(of: appElement, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return windows.enumerated().compactMap { index, window in
            AXUIElementSetMessagingTimeout(window, answerTimeout)
            guard let facts = facts(of: window), windowSubroles.contains(facts.subrole) else { return nil }
            return FoundWindow(item: item(for: facts, at: index, in: app), element: Element(ref: window))
        }
    }

    private static func item(for facts: WindowFacts, at index: Int, in app: RunningApp) -> Item {
        Item(
            id: "window:\(app.pid):\(index)",
            kind: .window,
            title: facts.title.isEmpty ? app.name : facts.title,
            detail: facts.isMinimised ? "\(app.name), minimised" : app.name,
            owner: app.name,
            lastUsed: app.isFrontmost && facts.isMain ? Date() : nil,
            payload: [
                "pid": "\(app.pid)",
                "frame": [facts.position.x, facts.position.y, facts.size.width, facts.size.height]
                    .map { "\(Int($0))" }.joined(separator: ","),
                "minimised": "\(facts.isMinimised)",
            ]
        )
    }

    // One message per window instead of one per attribute.
    private static func facts(of window: AXUIElement) -> WindowFacts? {
        var raw: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(window, factNames as CFArray, [], &raw)
        guard status == .success, let values = raw as? [AnyObject], values.count == factNames.count else {
            return nil
        }
        var facts = WindowFacts()
        facts.title = values[0] as? String ?? ""
        facts.subrole = values[1] as? String ?? ""
        facts.isMinimised = values[2] as? Bool ?? false
        facts.isMain = values[3] as? Bool ?? false
        if let position = geometry(values[4]) { AXValueGetValue(position, .cgPoint, &facts.position) }
        if let size = geometry(values[5]) { AXValueGetValue(size, .cgSize, &facts.size) }
        return facts
    }

    private static func geometry(_ value: AnyObject) -> AXValue? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private static func value(of element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func pid(of item: Item) -> pid_t? {
        item.payload["pid"].flatMap { pid_t($0) }
    }

    @MainActor private static func frontmost() -> (pid: pid_t, window: Element?)? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, answerTimeout)
        guard let focused = value(of: appElement, kAXFocusedWindowAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return (pid, nil)
        }
        return (pid, Element(ref: focused as! AXUIElement))
    }

    /// Returns false when the window or its app no longer exists.
    private static func focus(_ window: Element?, in pid: pid_t) -> Bool {
        if let window, !raise(window.ref) { return false }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, actionTimeout)
        return AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            == .success
    }

    /// Presses the window's own close button, so the app still asks about unsaved changes.
    private static func close(_ window: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(window, actionTimeout)
        guard let button = value(of: window, kAXCloseButtonAttribute) else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    private static func raise(_ window: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(window, actionTimeout)
        if value(of: window, kAXMinimizedAttribute) as? Bool == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else { return false }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        return true
    }
}
