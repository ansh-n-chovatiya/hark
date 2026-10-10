import AppKit
import ApplicationServices
import HarkCore

private struct ArrangeToolError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

public struct ArrangeWindowTool: Tool {
    public init() {}

    public var spec: ToolSpec {
        ToolSpec(
            name: "arrange_window",
            description: "Move and resize the front window of a running app, or of the app in front when none is "
                + "named, to a place on its screen. Call it once per window. \"full\" fills the screen without "
                + "entering full-screen mode, \"centre\" keeps the size, and \"next_screen\" moves it to the next "
                + "display.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "app": .object(["type": .string("string"), "description": .string("Name of a running app")]),
                    "place": .object([
                        "type": .string("string"),
                        "enum": .array(WindowPlace.allCases.map { .string($0.rawValue) }),
                    ]),
                ]),
                "required": .array([.string("place")]),
            ]),
            kind: .action)
    }

    public func describe(_ arguments: JSONValue) -> String {
        let subject = ArrangeArguments.appName(arguments) ?? "the front window"
        guard let place = try? ArrangeArguments.place(arguments) else { return "Move \(subject)" }
        return place.wording(for: subject).present
    }

    public func call(_ arguments: JSONValue) async throws -> ToolResult {
        let place = try ArrangeArguments.place(arguments)
        let app = try await ArrangeApps.target(named: ArrangeArguments.appName(arguments))
        guard AXIsProcessTrusted() else {
            throw ArrangeToolError(message: "Hark needs the Accessibility permission to move windows.")
        }
        guard let window = ArrangedWindow.front(of: app.processIdentifier) else {
            throw ArrangeToolError(message: "\(app.name) has no window open.")
        }
        await window.bringBack()
        try await MenuToolApps.bringForward(app.running)
        guard let before = window.frame else {
            throw ArrangeToolError(message: "\(app.name) does not say where its window is.")
        }
        let wanted = try await Screens.frame(for: place, window: before)
        guard let after = window.move(to: wanted) else {
            throw ArrangeToolError(message: "\(app.name) does not say where its window is.")
        }
        let wording = place.wording(for: app.name)
        let undo = UndoStep(summary: "Put the \(app.name) window back") { _ = window.move(to: before) }
        guard WindowPlaces.isClose(after, to: wanted, within: ArrangedWindow.tolerance) else {
            guard after != before else {
                throw ArrangeToolError(message: "\(app.name) did not let its window be moved.")
            }
            let size = "\(Int(after.width)) by \(Int(after.height))"
            return ToolResult(
                output: "\(wording.past), but \(app.name) keeps its own size there: \(size) points.",
                summary: wording.past, undo: undo)
        }
        return ToolResult(output: wording.past + ".", summary: wording.past, undo: undo)
    }
}

private enum ArrangeArguments {
    static func appName(_ arguments: JSONValue) -> String? {
        arguments["app"]?.string.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func place(_ arguments: JSONValue) throws -> WindowPlace {
        guard let text = arguments["place"]?.string, !text.isEmpty else {
            throw ArrangeToolError(message: "No place was given.")
        }
        guard let place = WindowPlace(rawValue: text.lowercased()) else {
            throw ArrangeToolError(message: "\"\(text)\" is not a place Hark knows.")
        }
        return place
    }
}

private extension WindowPlace {
    func wording(for subject: String) -> (present: String, past: String) {
        let verbs = self == .full ? ("Make", "Made") : ("Move", "Moved")
        return ("\(verbs.0) \(subject) \(ending)", "\(verbs.1) \(subject) \(ending)")
    }

    private var ending: String {
        switch self {
        case .left: "to the left half"
        case .right: "to the right half"
        case .top: "to the top half"
        case .bottom: "to the bottom half"
        case .topLeft: "to the top left quarter"
        case .topRight: "to the top right quarter"
        case .bottomLeft: "to the bottom left quarter"
        case .bottomRight: "to the bottom right quarter"
        case .leftThird: "to the left third"
        case .middleThird: "to the middle third"
        case .rightThird: "to the right third"
        case .leftTwoThirds: "to the left two thirds"
        case .rightTwoThirds: "to the right two thirds"
        case .full: "full size"
        case .centre: "to the centre"
        case .nextScreen: "to the next screen"
        }
    }
}

private struct ArrangeApp: Sendable {
    let running: NSRunningApplication
    let name: String

    var processIdentifier: pid_t { running.processIdentifier }
}

private enum ArrangeApps {
    @MainActor static func target(named name: String?) throws -> ArrangeApp {
        if let name {
            let app = try MenuToolApps.running(named: name)
            return ArrangeApp(running: app, name: app.localizedName ?? name)
        }
        guard let front = NSWorkspace.shared.frontmostApplication else {
            throw ArrangeToolError(message: "No app is in front.")
        }
        return ArrangeApp(running: front, name: front.localizedName ?? "the app in front")
    }
}

private enum Screens {
    private struct Screen {
        let whole: CGRect
        let usable: CGRect
    }

    @MainActor static func frame(for place: WindowPlace, window: CGRect) throws -> CGRect {
        let screens = all()
        guard let index = WindowPlaces.screenIndex(of: window, in: screens.map(\.whole)) else {
            throw ArrangeToolError(message: "No screen was found.")
        }
        guard place == .nextScreen else {
            return WindowPlaces.frame(for: place, window: window, in: screens[index].usable)
        }
        guard let next = WindowPlaces.nextIndex(after: index, count: screens.count) else {
            throw ArrangeToolError(message: "There is only one screen.")
        }
        return WindowPlaces.frame(of: window, movedFrom: screens[index].usable, to: screens[next].usable)
    }

    /// The first screen is the one with the menu bar, whose height both coordinate systems hang on.
    @MainActor private static func all() -> [Screen] {
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.map { screen in
            Screen(
                whole: WindowPlaces.topLeft(fromBottomLeft: screen.frame, mainHeight: mainHeight),
                usable: WindowPlaces.topLeft(fromBottomLeft: screen.visibleFrame, mainHeight: mainHeight))
        }
    }
}

// AXUIElement is an immutable handle to another process; every call on it is a message to that
// process, so sharing it across tasks is safe even though the type is not marked Sendable.
private struct ArrangedWindow: @unchecked Sendable {
    // Terminals snap to whole character cells, so they land a few points short of what was asked.
    static let tolerance: CGFloat = 20
    // Restoring a minimised window answers only after its animation.
    private static let timeout: Float = 2
    private static let restoreTime = Duration.milliseconds(500)

    let ref: AXUIElement

    static func front(of pid: pid_t) -> ArrangedWindow? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        let window = element(value(app, kAXFocusedWindowAttribute)) ?? element(value(app, kAXMainWindowAttribute))
            ?? (value(app, kAXWindowsAttribute) as? [AXUIElement])?.first
        guard let window else { return nil }
        AXUIElementSetMessagingTimeout(window, timeout)
        return ArrangedWindow(ref: window)
    }

    /// Un-minimises the window and puts it in front of the app's other windows.
    func bringBack() async {
        if Self.value(ref, kAXMinimizedAttribute) as? Bool == true {
            AXUIElementSetAttributeValue(ref, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            try? await Task.sleep(for: Self.restoreTime)
        }
        AXUIElementPerformAction(ref, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(ref, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    var frame: CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = Self.geometry(Self.value(ref, kAXPositionAttribute)),
              let extent = Self.geometry(Self.value(ref, kAXSizeAttribute)),
              AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(extent, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Returns the frame the window ended up with. The position is set twice because a window
    /// is kept on its screen while it still has its old size, and may move as it resizes.
    func move(to frame: CGRect) -> CGRect? {
        set(position: frame.origin)
        set(size: frame.size)
        set(position: frame.origin)
        return self.frame
    }

    private func set(position: CGPoint) {
        var point = position
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(ref, kAXPositionAttribute as CFString, value)
    }

    private func set(size: CGSize) {
        var extent = size
        guard let value = AXValueCreate(.cgSize, &extent) else { return }
        AXUIElementSetAttributeValue(ref, kAXSizeAttribute as CFString, value)
    }

    private static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func geometry(_ value: AnyObject?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
