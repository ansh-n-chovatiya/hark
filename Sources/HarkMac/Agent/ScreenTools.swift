import AppKit
import ApplicationServices
import HarkCore
import Synchronization

/// The tools that read and press the controls inside an app's window. They share one registry
/// of element ids, so call this once per command.
public enum ScreenTools {
    public static func all() -> [any Tool] {
        let controls = ScreenControls()
        return [
            LookAtAppTool(controls: controls),
            PressElementTool(controls: controls),
            SetFieldTool(controls: controls),
        ]
    }
}

private struct ScreenToolError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }

    static let gone = ScreenToolError(message: "That control has changed or gone. Call look_at_app again.")
}

private struct LookAtAppTool: Tool {
    let spec = ToolSpec(
        name: "look_at_app",
        description: "List the buttons, links, tabs, menus, checkboxes and text boxes in the front window of a "
            + "running app, or of the app in front when none is named. Each line starts with an id for "
            + "press_element and set_field. Ids stop working at the next look_at_app.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "app": .object(["type": .string("string"), "description": .string("Name of a running app")]),
            ]),
        ]),
        kind: .lookup)

    let controls: ScreenControls

    func describe(_ arguments: JSONValue) -> String {
        "Look at \(arguments["app"]?.string ?? "the app in front")"
    }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        let app = try await ScreenApps.target(named: arguments["app"]?.string)
        guard AXIsProcessTrusted() else {
            throw ScreenToolError(message: "Hark needs the Accessibility permission to read an app's controls.")
        }
        let appElement = AXUIElementCreateApplication(app.pid)
        if ScreenApps.wake(appElement) { try? await Task.sleep(for: ScreenApps.wakeTime) }
        guard let window = AX.frontWindow(of: appElement) else {
            throw ScreenToolError(message: "\(app.name) has no window open.")
        }
        var scan = WindowScan(window: window, app: app)
        scan.run()
        let title = AX.value(window, kAXTitleAttribute) as? String ?? ""
        var lines = ["Window: \(title.isEmpty ? app.name : "\(Label.tidy(title)) (\(app.name))")"]
        lines += controls.replace(with: scan.found)
        if scan.found.isEmpty { lines.append("No controls found in this window.") }
        if scan.wasCut { lines.append("(list cut: this window has more controls than are shown)") }
        return ToolResult(output: lines.joined(separator: "\n"))
    }
}

private struct PressElementTool: Tool {
    let spec = ToolSpec(
        name: "press_element",
        description: "Press a control that look_at_app listed, by its id. Call look_at_app again afterwards to "
            + "see what changed.",
        parameters: ScreenArguments.schema(extra: [:], required: ["id"]),
        kind: .action)

    let controls: ScreenControls

    func describe(_ arguments: JSONValue) -> String {
        let id = ScreenArguments.id(arguments)
        guard let control = try? controls.control(id) else { return "Press \(id)" }
        return "\(control.isText ? "Submit" : "Press") \(control.name) in \(control.app)"
    }

    func kind(for arguments: JSONValue) -> ToolKind {
        guard let control = try? controls.control(ScreenArguments.id(arguments)) else { return .action }
        // Pressing a text box confirms it, which sends whatever it holds.
        return control.isText || ScreenSafety.asksFirst(control.wording) ? .destructive : .action
    }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        let control = try controls.control(ScreenArguments.id(arguments))
        try ScreenSafety.refuseDeletion(control)
        try control.checkUnchanged()
        guard let action = Press.action(for: control) else {
            throw ScreenToolError(message: "\(control.name) in \(control.app) cannot be pressed.")
        }
        try await ScreenApps.bringForward(control)
        guard Press.perform(action, on: control.element.ref) else {
            throw ScreenToolError(message: "\(control.app) did not accept the press on \(control.name).")
        }
        let summary = "\(control.isText ? "Submitted" : "Pressed") \(control.name) in \(control.app)"
        return ToolResult(output: summary + ".", summary: summary)
    }
}

private struct SetFieldTool: Tool {
    let spec = ToolSpec(
        name: "set_field",
        description: "Put text into a text box or text area that look_at_app listed, by its id. It replaces what "
            + "the box holds and presses no keys, so nothing is sent or submitted.",
        parameters: ScreenArguments.schema(extra: ["text": .object(["type": .string("string")])], required: ["id", "text"]),
        kind: .action)

    let controls: ScreenControls

    func describe(_ arguments: JSONValue) -> String {
        let id = ScreenArguments.id(arguments)
        let text = arguments["text"]?.string ?? ""
        guard let control = try? controls.control(id) else { return "Type '\(text)' into \(id)" }
        guard control.holdsText else { return "Type '\(text)' into \(control.name) in \(control.app)" }
        return "Replace the text in \(control.name) in \(control.app) with '\(text)'"
    }

    func kind(for arguments: JSONValue) -> ToolKind {
        guard let control = try? controls.control(ScreenArguments.id(arguments)) else { return .action }
        // What the box already holds cannot be put back, so replacing it is the user's call.
        return control.holdsText || ScreenSafety.asksFirst(control.wording) ? .destructive : .action
    }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        let control = try controls.control(ScreenArguments.id(arguments))
        guard let text = arguments["text"]?.string, !text.isEmpty else {
            throw ScreenToolError(message: "No text was given.")
        }
        try ScreenSafety.refuseDeletion(control)
        try control.checkUnchanged()
        guard control.isText else {
            throw ScreenToolError(message: "\(control.name) is a \(control.word), not a text box.")
        }
        guard !control.isSecure else {
            throw ScreenToolError(message: "Hark does not type into password fields.")
        }
        guard AX.isSettable(control.element.ref, kAXValueAttribute) else {
            throw ScreenToolError(message: "\(control.name) in \(control.app) does not take text this way.")
        }
        try await ScreenApps.bringForward(control)
        guard await TextValue.put(text, into: control) else {
            throw ScreenToolError(message: "\(control.name) in \(control.app) did not take the text.")
        }
        let summary = "Typed '\(text)' into \(control.name) in \(control.app)"
        return ToolResult(output: summary + ".", summary: summary)
    }
}

/// Pressing something in the window in front by the words on it, by rule: "open my personal DM" finds
/// the list item, button or tab whose label fits. It uses the same scan and the same fences as the
/// model's tools. Nothing is pressed unless one control clearly fits.
enum FrontWindow {
    struct Target: Sendable {
        let app: String
        let label: String
        /// The control is about sending, posting, paying, joining or leaving: it asks first.
        let needsYes: Bool
        let press: @Sendable () async throws -> String
    }

    enum Found {
        case none
        case unsure([String])
        case refused(String)
        case ready(Target)
    }

    static func look(for phrase: String) async -> Found {
        guard AXIsProcessTrusted(), let app = await MainActor.run(body: { try? ScreenApps.target(named: nil) }) else {
            return .none
        }
        let element = AXUIElementCreateApplication(app.pid)
        if ScreenApps.wake(element) { try? await Task.sleep(for: ScreenApps.wakeTime) }
        guard let window = AX.frontWindow(of: element) else { return .none }
        var scan = WindowScan(window: window, app: app)
        scan.run()
        // A text box is never pressed here: pressing one sends what it holds.
        let candidates = scan.found.filter { !$0.isText && !$0.label.isEmpty }
        switch AppAction.chooseLabel(phrase, among: candidates.map(\.label)) {
        case .none:
            return .none
        case .unsure(let indexes):
            return .unsure(indexes.prefix(3).map { candidates[$0].label })
        case .label(let index):
            let control = candidates[index]
            do {
                try ScreenSafety.refuseDeletion(control)
            } catch {
                return .refused(error.localizedDescription)
            }
            return .ready(Target(
                app: control.app, label: control.label, needsYes: ScreenSafety.asksFirst(control.wording),
                press: {
                    try control.checkUnchanged()
                    guard let action = Press.action(for: control) else {
                        throw ScreenToolError(message: "\(control.name) in \(control.app) cannot be pressed.")
                    }
                    try await ScreenApps.bringForward(control)
                    guard Press.perform(action, on: control.element.ref) else {
                        throw ScreenToolError(message: "\(control.app) did not accept the press on \(control.name).")
                    }
                    return "Pressed \(control.name) in \(control.app)"
                }))
        }
    }
}

private enum ScreenArguments {
    static func schema(extra: [String: JSONValue], required: [String]) -> JSONValue {
        let id: JSONValue = .object(["type": .string("string"), "description": .string("An id from look_at_app, such as e4")])
        return .object([
            "type": .string("object"),
            "properties": .object(extra.merging(["id": id]) { _, new in new }),
            "required": .array(required.map(JSONValue.string)),
        ])
    }

    static func id(_ arguments: JSONValue) -> String {
        arguments["id"]?.string ?? ""
    }
}

// AXUIElement is an immutable handle to another process; every call on it is a message to that
// process, so sharing it across tasks is safe even though the type is not marked Sendable.
private struct ScreenElement: @unchecked Sendable {
    let ref: AXUIElement
}

private struct ScreenApp: Sendable {
    let pid: pid_t
    let name: String
}

private struct Control: Sendable {
    let element: ScreenElement
    let word: String
    let label: String
    /// Everything the control says about itself. Safety is judged on this, and a control whose
    /// wording has changed since it was listed is no longer the one the model chose.
    let wording: String
    let detail: String
    let app: String
    let pid: pid_t

    var isText: Bool { Words.text.contains(word) }
    var name: String { label.isEmpty ? "the \(word)" : label }
    var line: String { label.isEmpty ? word + detail : "\(word): \(label)\(detail)" }

    var isSecure: Bool {
        word == Words.password || AX.value(element.ref, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
    }

    var holdsText: Bool {
        guard isText, !isSecure else { return false }
        return TextValue.start(of: element.ref, isArea: word == Words.area)?.text.isEmpty == false
    }

    func checkUnchanged() throws {
        guard let facts = ElementFacts(of: element.ref),
              Label.read(facts, word: word).wording == wording else { throw ScreenToolError.gone }
        guard facts.isEnabled else { throw ScreenToolError(message: "\(name) in \(app) is greyed out.") }
    }
}

/// The controls the last look_at_app found, under the ids it gave them.
private final class ScreenControls: Sendable {
    private let found = Mutex<[String: Control]>([:])

    func replace(with controls: [Control]) -> [String] {
        found.withLock { found in
            found = [:]
            return controls.enumerated().map { index, control in
                let id = "e\(index + 1)"
                found[id] = control
                return "\(id) \(control.line)"
            }
        }
    }

    /// Models sometimes answer with a control's label where an id was asked for, so a label that
    /// matches exactly one control is accepted too.
    func control(_ reference: String) throws -> Control {
        try found.withLock { found in
            if let control = found[reference.lowercased()] { return control }
            let named = found.values.filter { $0.label.caseInsensitiveCompare(reference) == .orderedSame }
            guard named.count == 1 else {
                throw ScreenToolError(message: "There is no control \"\(reference)\". Call look_at_app again.")
            }
            return named[0]
        }
    }
}

/// Pressing is the widest door a model has into an app, so it is fenced by what the control says
/// it does: nothing about deleting, and a yes first for what cannot be put back (decision 0008).
private enum ScreenSafety {
    private static let moreDeletionStems = ["format", "wipe", "wiping"]
    private static let askFirstStems = [
        "close", "closing", "quit", "exit", "logout", "signout", "shutdown", "restart", "send", "post", "submit",
        "publish", "share", "sharing", "pay", "buy", "purchas", "order", "confirm", "accept", "agree", "call",
        "join", "leave", "leaving", "block", "merge", "merging", "deploy", "run", "install", "approv", "reject",
    ]
    private static let askFirstPhrases = ["log out", "sign out", "shut down"]

    static func refuseDeletion(_ control: Control) throws {
        guard let word = deletionWord(in: control.wording) else { return }
        throw ScreenToolError(message: "Hark does not use controls about \"\(word)\".")
    }

    static func asksFirst(_ wording: String) -> Bool {
        let lowered = wording.lowercased()
        return askFirstPhrases.contains(where: lowered.contains)
            || words(in: lowered).contains { word in askFirstStems.contains(where: word.hasPrefix) }
    }

    private static func deletionWord(in wording: String) -> String? {
        MenuSafety.deletionWord(in: wording)
            ?? words(in: wording.lowercased()).first { word in moreDeletionStems.contains(where: word.hasPrefix) }
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter }).map(String.init)
    }
}

private enum ScreenApps {
    static let wakeTime = Duration.milliseconds(400)

    @MainActor static func target(named name: String?) throws -> ScreenApp {
        let app: NSRunningApplication
        if let name, !name.isEmpty {
            app = try MenuToolApps.running(named: name)
        } else if let front = NSWorkspace.shared.frontmostApplication {
            app = front
        } else {
            throw ScreenToolError(message: "No app is in front.")
        }
        guard !KeySafety.isTerminal(app) else {
            throw ScreenToolError(message: "Hark does not look at or press anything in a terminal.")
        }
        return ScreenApp(pid: app.processIdentifier, name: app.localizedName ?? name ?? "the app")
    }

    @MainActor static func bringForward(_ control: Control) async throws {
        guard let app = NSRunningApplication(processIdentifier: control.pid) else { throw ScreenToolError.gone }
        try await MenuToolApps.bringForward(app)
    }

    /// Browser and Electron apps build their Accessibility tree only once something asks for it.
    /// Returns true when this call was the one that asked, so the tree needs a moment to appear.
    static func wake(_ app: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(app, AX.timeout)
        let wasAwake = AX.value(app, enhancedInterface) as? Bool == true
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, enhancedInterface as CFString, kCFBooleanTrue)
        return !wasAwake
    }

    private static let enhancedInterface = "AXEnhancedUserInterface"
}

private enum Words {
    static let box = "text box"
    static let area = "text area"
    static let password = "password box"
    static let text: Set<String> = [box, area, password]
    static let menu = "menu"
    static let row = "row"
    /// Rows and cells are everywhere in a window; only the ones that answer a press are controls.
    static let needsPress: Set<String> = [row]
    /// A text box is known by where it is and what it holds, so it is listed without a label.
    static let needsNoLabel = text

    static func word(for facts: ElementFacts, inTabs: Bool) -> String? {
        switch facts.role {
        case kAXButtonRole: "button"
        case "AXLink": "link"
        case kAXRadioButtonRole: inTabs || facts.subrole == "AXTabButton" ? "tab" : "radio button"
        case kAXPopUpButtonRole, kAXMenuButtonRole: menu
        case kAXCheckBoxRole: "checkbox"
        case kAXTextFieldRole, kAXComboBoxRole: facts.subrole == kAXSecureTextFieldSubrole ? password : box
        case kAXTextAreaRole: area
        case kAXRowRole, kAXCellRole: row
        case kAXMenuItemRole: "menu item"
        default: nil
        }
    }
}

/// One walk over a window's tree, collecting the controls a person could use right now.
private struct WindowScan {
    private static let lineLimit = 150
    // Measured: a browser's page starts about 10 levels down and an Electron app's controls sit
    // 15 to 33 levels down, so a shallower walk finds nothing in them. The time budget is what
    // keeps a huge tree from holding a command.
    private static let depthLimit = 40
    private static let timeBudget: TimeInterval = 1.5

    private let window: AXUIElement
    private let app: ScreenApp
    private var frame = CGRect.infinite
    private var deadline = Date.distantFuture
    private(set) var found: [Control] = []
    private(set) var wasCut = false
    private var isOver = false

    init(window: AXUIElement, app: ScreenApp) {
        self.window = window
        self.app = app
    }

    mutating func run() {
        guard let facts = ElementFacts(of: window) else { return }
        frame = facts.frame ?? .infinite
        deadline = Date().addingTimeInterval(Self.timeBudget)
        for child in facts.children { walk(child, depth: 1, inTabs: false) }
    }

    private mutating func walk(_ element: AXUIElement, depth: Int, inTabs: Bool) {
        guard !isOver else { return }
        guard found.count < Self.lineLimit, Date() < deadline else {
            wasCut = true
            isOver = true
            return
        }
        guard let facts = ElementFacts(of: element), !isOutside(facts) else { return }
        if let control = control(for: facts, at: element, inTabs: inTabs) { found.append(control) }
        guard depth < Self.depthLimit else {
            if !facts.children.isEmpty { wasCut = true }
            return
        }
        let isTabs = facts.role == kAXTabGroupRole
        for child in facts.children { walk(child, depth: depth + 1, inTabs: isTabs) }
    }

    /// A container with no size of its own can still hold visible children, so only a real frame
    /// that misses the window rules a branch out.
    private func isOutside(_ facts: ElementFacts) -> Bool {
        guard let own = facts.frame, !own.isEmpty else { return false }
        return !own.intersects(frame)
    }

    private func control(for facts: ElementFacts, at element: AXUIElement, inTabs: Bool) -> Control? {
        guard let word = Words.word(for: facts, inTabs: inTabs), facts.isEnabled,
              let own = facts.frame, !own.isEmpty else { return nil }
        if Words.needsPress.contains(word), !AX.actions(of: element).contains(kAXPressAction) { return nil }
        let read = Label.read(facts, word: word)
        guard !read.label.isEmpty || Words.needsNoLabel.contains(word) else { return nil }
        return Control(
            element: ScreenElement(ref: element), word: word, label: read.label, wording: read.wording,
            detail: Detail.read(element, word: word, label: read.label), app: app.name, pid: app.pid)
    }
}

/// What one element says about itself, fetched in a single message.
private struct ElementFacts {
    private static let names = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXEnabledAttribute,
        kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute, kAXTitleUIElementAttribute,
        kAXPlaceholderValueAttribute,
    ]

    let role: String
    let subrole: String
    let title: String
    let description: String
    let isEnabled: Bool
    let frame: CGRect?
    let children: [AXUIElement]
    let titleElement: AXUIElement?
    let placeholder: String

    /// Nil when the element no longer exists or its app does not answer.
    init?(of element: AXUIElement) {
        guard let values = AX.values(element, Self.names), let role = values[0] as? String else { return nil }
        self.role = role
        subrole = values[1] as? String ?? ""
        title = values[2] as? String ?? ""
        description = values[3] as? String ?? ""
        isEnabled = values[4] as? Bool ?? true
        frame = AX.frame(position: values[5], size: values[6])
        children = values[7] as? [AXUIElement] ?? []
        titleElement = AX.element(values[8])
        placeholder = values[9] as? String ?? ""
    }
}

private enum Label {
    private static let longest = 80
    private static let innerDepth = 3
    private static let innerTexts = 2

    static func read(_ facts: ElementFacts, word: String) -> (label: String, wording: String) {
        let label = tidy(firstLabel(of: facts, word: word))
        return (label, [facts.title, facts.description, label].joined(separator: " "))
    }

    static func tidy(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.count > longest ? String(words.prefix(longest)) + "…" : words
    }

    private static func firstLabel(of facts: ElementFacts, word: String) -> String {
        if !facts.title.isEmpty { return facts.title }
        if !facts.description.isEmpty { return facts.description }
        if let titled = facts.titleElement.flatMap(text(of:)), !titled.isEmpty { return titled }
        if Words.text.contains(word) { return facts.placeholder }
        var texts: [String] = []
        collectTexts(under: facts.children, depth: innerDepth, into: &texts)
        return texts.joined(separator: ", ")
    }

    private static func text(of element: AXUIElement) -> String? {
        AX.value(element, kAXTitleAttribute) as? String ?? AX.value(element, kAXValueAttribute) as? String
    }

    /// Rows and web links keep their words in text elements beneath them. Only static text is
    /// read, so what someone typed into a box inside a row never becomes part of a label.
    private static func collectTexts(under children: [AXUIElement], depth: Int, into texts: inout [String]) {
        for child in children where texts.count < innerTexts {
            guard let values = AX.values(child, [kAXRoleAttribute, kAXChildrenAttribute]) else { continue }
            if values[0] as? String == kAXStaticTextRole {
                if let text = AX.value(child, kAXValueAttribute) as? String, !text.isEmpty { texts.append(text) }
            } else if depth > 1 {
                collectTexts(under: values[1] as? [AXUIElement] ?? [], depth: depth - 1, into: &texts)
            }
        }
    }
}

/// The state shown after a control's label: what a box holds, whether a checkbox is on.
private enum Detail {
    static func read(_ element: AXUIElement, word: String, label: String) -> String {
        switch word {
        case Words.password: return ""
        case Words.box, Words.area: return text(in: element, isArea: word == Words.area)
        case Words.menu:
            guard let chosen = AX.value(element, kAXValueAttribute) as? String, !chosen.isEmpty, chosen != label else {
                return ""
            }
            return " (\(Label.tidy(chosen)))"
        case "checkbox": return isOn(element) ? " (on)" : " (off)"
        case "tab", "radio button": return isOn(element) ? " (selected)" : ""
        default: return ""
        }
    }

    private static func text(in element: AXUIElement, isArea: Bool) -> String {
        guard let start = TextValue.start(of: element, isArea: isArea), !start.text.isEmpty else { return "" }
        let shown = start.text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return " = \"\(shown)\(start.isCut ? "…" : "")\""
    }

    private static func isOn(_ element: AXUIElement) -> Bool {
        (AX.value(element, kAXValueAttribute) as? NSNumber)?.intValue == 1
    }
}

private enum TextValue {
    private static let shownLength = 60

    /// Only the part that is shown is fetched, so a long document never enters Hark. A text area
    /// that cannot hand over just its start is left unread.
    static func start(of element: AXUIElement, isArea: Bool) -> (text: String, isCut: Bool)? {
        if let count = AX.value(element, kAXNumberOfCharactersAttribute) as? Int {
            if count == 0 { return ("", false) }
            var range = CFRange(location: 0, length: min(count, shownLength))
            if let wanted = AXValueCreate(.cfRange, &range),
               let text = AX.value(element, kAXStringForRangeParameterizedAttribute, for: wanted) as? String {
                return (text, count > shownLength)
            }
        }
        guard !isArea, let whole = AX.value(element, kAXValueAttribute) as? String else { return nil }
        return (String(whole.prefix(shownLength)), whole.count > shownLength)
    }

    /// Sets the value and focuses the box; no key is pressed. Web pages take a value a moment
    /// after it is set, so the check is tried a few times.
    static func put(_ text: String, into control: Control) async -> Bool {
        let element = control.element.ref
        AXUIElementSetMessagingTimeout(element, AX.actionTimeout)
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString) == .success else {
            return false
        }
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        for _ in 0..<3 {
            guard let start = start(of: element, isArea: control.word == Words.area) else { return true }
            if !start.text.isEmpty, text.hasPrefix(start.text) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}

private enum Press {
    private static let ways = [kAXPressAction, kAXConfirmAction, kAXPickAction, kAXShowMenuAction]

    /// A text box can only be confirmed: its other action opens the right-click menu.
    static func action(for control: Control) -> String? {
        let offered = AX.actions(of: control.element.ref)
        return (control.isText ? [kAXConfirmAction] : ways).first(where: offered.contains)
    }

    static func perform(_ action: String, on element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, AX.actionTimeout)
        return AXUIElementPerformAction(element, action as CFString) == .success
    }
}

private enum AX {
    // An app that is busy or hung would otherwise hold each message for the six second system default.
    static let timeout: Float = 0.3
    static let actionTimeout: Float = 2

    static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func value(_ element: AXUIElement, _ name: String, for parameter: AXValue) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success else {
            return nil
        }
        return value
    }

    static func values(_ element: AXUIElement, _ names: [String]) -> [AnyObject]? {
        AXUIElementSetMessagingTimeout(element, timeout)
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &raw) == .success,
              let values = raw as? [AnyObject], values.count == names.count else { return nil }
        return values
    }

    static func element(_ value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func actions(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    static func frontWindow(of app: AXUIElement) -> AXUIElement? {
        element(value(app, kAXFocusedWindowAttribute)) ?? element(value(app, kAXMainWindowAttribute))
            ?? (value(app, kAXWindowsAttribute) as? [AXUIElement])?.first
    }

    static func frame(position: AnyObject, size: AnyObject) -> CGRect? {
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
