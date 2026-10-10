import AppKit
import ApplicationServices
import Carbon.HIToolbox

public enum TextTyperError: LocalizedError {
    case notAllowed, passwordField, nothingFocused

    public var errorDescription: String? {
        switch self {
        case .notAllowed: "Hark needs the Accessibility permission to type for you."
        case .passwordField: "A password field is selected, so Hark did not type."
        case .nothingFocused: "There is no text box to type into."
        }
    }
}

/// Kinds of focused element that take typed text.
private let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]

/// Types the user's own words into whatever has the keyboard focus, as key presses, so it works in
/// any app. It sends only text: never Return, Tab, a shortcut or any other key, and it does not
/// use the clipboard. (When there is nowhere to type, the caller copies the words to the clipboard instead.)
public enum TextTyper {
    /// Long text goes in small pieces: some apps drop characters from a single large event.
    private static let piece = 16

    @MainActor public static func type(_ text: String) async throws {
        guard AXIsProcessTrusted() else { throw TextTyperError.notAllowed }
        // macOS turns on secure input while a password field is focused, in any app.
        guard !IsSecureEventInputEnabled() else { throw TextTyperError.passwordField }
        try checkFocus()
        guard let source = CGEventSource(stateID: .combinedSessionState) else { throw TextTyperError.notAllowed }
        let units = Array(text.utf16)
        var start = 0
        while start < units.count {
            // Never cut a character in half: a surrogate pair stays whole.
            var end = min(start + piece, units.count)
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            let chunk = Array(units[start..<end])
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.post(tap: .cghidEventTap)
            }
            start = end
            try? await Task.sleep(for: .milliseconds(4))
        }
    }

    /// Refuses a focused password box, and an app with nothing focused to type into.
    private static func checkFocus() throws {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused
        else { throw TextTyperError.nothingFocused }
        // swiftlint:disable:next force_cast
        let ref = element as! AXUIElement
        var subrole: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(ref, kAXSubroleAttribute as CFString, &subrole)
        if (subrole as? String) == (kAXSecureTextFieldSubrole as String) { throw TextTyperError.passwordField }
        // Only a text box is typed at. Anything else, such as a row or a page, would turn the letters into the
        // page's single-key shortcuts (archive, delete, mark as spam). A custom editor that reports another
        // role still has a text selection, which is what is looked for.
        var role: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(ref, kAXRoleAttribute as CFString, &role)
        if let role = role as? String, textRoles.contains(role) { return }
        var selection: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, kAXSelectedTextRangeAttribute as CFString, &selection) == .success else {
            throw TextTyperError.nothingFocused
        }
    }
}
