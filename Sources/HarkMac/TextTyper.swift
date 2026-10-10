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

    /// The element that has the keyboard. The app in front is asked first: asking the whole system often fails
    /// (error -25204, "cannot complete") even when the permission is granted, while asking the app works.
    private static func focusedElement() -> AXUIElement? {
        if let app = NSWorkspace.shared.frontmostApplication {
            var found: CFTypeRef?
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 1)
            if AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &found) == .success,
               let found, CFGetTypeID(found) == AXUIElementGetTypeID() {
                // swiftlint:disable:next force_cast
                return (found as! AXUIElement)
            }
        }
        var found: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &found) == .success,
              let found, CFGetTypeID(found) == AXUIElementGetTypeID()
        else { return nil }
        // swiftlint:disable:next force_cast
        return (found as! AXUIElement)
    }

    /// What dictation would do right now, in words, without typing anything: for checking an app.
    public static func verdict() -> String {
        guard AXIsProcessTrusted() else { return "Accessibility is not allowed, so Hark could not type." }
        guard let ref = focusedElement() else {
            if let app = NSWorkspace.shared.frontmostApplication, KeySafety.isTerminal(app) {
                return "Would type here (a terminal)."
            }
            return "Nothing is focused: the words would be copied to the clipboard."
        }
        var role: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(ref, kAXRoleAttribute as CFString, &role)
        let name = (role as? String) ?? "unknown"
        do {
            try checkFocus()
            return "Would type here (focused element: \(name))."
        } catch TextTyperError.passwordField {
            return "A password field: nothing is typed or copied (\(name))."
        } catch {
            return "No text box (focused element: \(name)): the words would be copied to the clipboard."
        }
    }

    /// Refuses a focused password box, and an app with nothing focused to type into.
    private static func checkFocus() throws {
        guard let ref = focusedElement() else {
            // A terminal with nothing reported as focused still has a prompt; its letters can only land there.
            if let app = NSWorkspace.shared.frontmostApplication, KeySafety.isTerminal(app) { return }
            throw TextTyperError.nothingFocused
        }
        var subrole: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(ref, kAXSubroleAttribute as CFString, &subrole)
        if (subrole as? String) == (kAXSecureTextFieldSubrole as String) { throw TextTyperError.passwordField }
        // Only a text box is typed at. Anything else, such as a row, an outline or a page, would turn the letters into
        // the app's or page's single-key shortcuts (archive, delete, mark as spam). So: a text role; or an element a
        // browser marks as editable (editable page content has no text role); or a terminal, where letters only
        // ever land on the prompt.
        var role: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(ref, kAXRoleAttribute as CFString, &role)
        if let role = role as? String, textRoles.contains(role) { return }
        if let app = NSWorkspace.shared.frontmostApplication, KeySafety.isTerminal(app) { return }
        for attribute in ["AXEditableAncestor", "AXHighestEditableAncestor"] {
            var editable: CFTypeRef?
            if AXUIElementCopyAttributeValue(ref, attribute as CFString, &editable) == .success, editable != nil { return }
        }
        throw TextTyperError.nothingFocused
    }
}
