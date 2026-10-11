import AppKit
import ApplicationServices
import Carbon.HIToolbox
import HarkCore

public enum TextEditingError: LocalizedError {
    case notHere, changed

    public var errorDescription: String? {
        switch self {
        case .notHere: "I cannot edit text here."
        case .changed: "The text has changed, so I left it alone."
        }
    }
}

/// Edits the text Hark itself typed, and moves the cursor or selection, in the box that has the keyboard. Nothing is
/// changed unless the text just before the cursor is exactly what Hark typed (`TypedSpan`); the keys sent are arrows,
/// select-all and Delete on a selection, never Return.
@MainActor public enum TextEditing {
    /// What was typed last and where: only an edit right after it, in the same box, can find it again.
    private static var lastTyped: String?

    public static func typed(_ text: String) { lastTyped = text }
    public static func forget() { lastTyped = nil }

    private static func element() throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw TextTyperError.notAllowed }
        guard !IsSecureEventInputEnabled() else { throw TextTyperError.passwordField }
        try TextTyper.checkFocus()
        guard let element = TextTyper.focusedElement() else { throw TextEditingError.notHere }
        return element
    }

    private static func value(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func selection(of element: AXUIElement) -> NSRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(ref as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private static func select(_ range: NSRange, in element: AXUIElement) -> Bool {
        var cf = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cf) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    private static func selectedText(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    /// The span Hark typed, checked to be right before the cursor.
    private static func typedSpan(in element: AXUIElement) throws -> (range: NSRange, value: String) {
        guard let typed = lastTyped, let value = value(of: element), let caret = selection(of: element),
              caret.length == 0 else { throw TextEditingError.changed }
        guard let range = TypedSpan.range(of: typed, in: value, caret: caret.location) else { throw TextEditingError.changed }
        return (range, value)
    }

    public static func scratch() async throws -> String {
        let element = try element()
        let (range, _) = try typedSpan(in: element)
        guard select(range, in: element), selectedText(of: element) == lastTyped else { throw TextEditingError.changed }
        press(key: 51)
        lastTyped = nil
        return "Removed what I typed"
    }

    public static func replace(old: String, new: String) async throws -> String {
        let element = try element()
        let (span, value) = try typedSpan(in: element)
        guard let target = TypedSpan.target(old, inSpan: span, of: value),
              select(target, in: element) else { throw TextEditingError.changed }
        let before = (value as NSString).substring(with: target)
        guard selectedText(of: element) == before else { throw TextEditingError.changed }
        // A replacement keeps the case of what it replaces at the start of a sentence.
        let text = before.first?.isUppercase == true ? new.prefix(1).uppercased() + new.dropFirst() : new
        try await TextTyper.type(text)
        lastTyped = nil
        return "Changed \u{201C}\(before)\u{201D} to \u{201C}\(text)\u{201D}"
    }

    public static func move(_ move: DictationCommand.Move) throws -> String {
        let element = try element()
        switch move {
        case .lastWord: press(key: 123, flags: [.maskAlternate, .maskShift]); return "Selected the last word"
        case .line: press(key: 123, flags: [.maskCommand, .maskShift]); return "Selected the line"
        case .all: press(key: 0, flags: .maskCommand); return "Selected everything"
        case .start: press(key: 126, flags: .maskCommand); return "Went to the start"
        case .end: press(key: 125, flags: .maskCommand); return "Went to the end"
        }
        _ = element
    }

    /// Deletes the selection, only when there is one.
    public static func deleteSelection() throws -> String {
        let element = try element()
        guard let text = selectedText(of: element), !text.isEmpty else { throw TextEditingError.changed }
        press(key: 51)
        return "Deleted the selection"
    }

    private static func press(key: CGKeyCode, flags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
