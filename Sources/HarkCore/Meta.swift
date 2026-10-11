import Foundation

/// Things said about Hark's own last command rather than about the Mac: "why did you do that", "that was wrong",
/// "remember that as Kubernetes". They are settled by rule, never reach a model, and never replace the command they are
/// about as "the last one".
public enum MetaCommand: Equatable, Sendable {
    case why
    case whatHeard
    case wrong
    case remember(String)
    case help

    public static func parse(_ transcript: String) -> MetaCommand? {
        let words = normalizedWords(transcript)
        guard !words.isEmpty, words.count <= 12 else { return nil }
        var text = words.joined(separator: " ")
        for lead in ["hark ", "please ", "hey "] where text.hasPrefix(lead) { text.removeFirst(lead.count) }
        if ["why did you do that", "why did you do this", "why was that", "why", "explain that", "show details",
            "how did you decide"].contains(text) { return .why }
        if ["what did you hear", "what did you just hear", "read that back", "say that again", "what did i say"].contains(text) {
            return .whatHeard
        }
        if ["that was wrong", "that is wrong", "thats wrong", "that was not right", "wrong", "no that was wrong",
            "that is not what i meant", "that was not what i meant"].contains(text) { return .wrong }
        for lead in ["remember that as ", "remember that is ", "that should be ", "i meant ", "no i meant "]
        where text.hasPrefix(lead) {
            let name = String(text.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : .remember(name)
        }
        if ["what can i say", "help", "help me", "what can you do", "show me what i can say", "examples"].contains(text) {
            return .help
        }
        return nil
    }
}

extension Timings {
    /// Plain words for which part of Hark settled the command.
    public var decidedBy: String {
        if let model { return "the model (\(model))" }
        switch verb {
        case "search": return "the web search rule"
        case "siteSearch": return "the site search rule"
        case "system": return "the system settings rule"
        case "frontAction": return "the menus and buttons of the app in front"
        case "appAction": return "the menus of the app you named"
        case "arrange": return "the window layout rule"
        case "copy": return "the copy rule"
        case "openIn": return "the open-in-an-app rule"
        case "run": return "a routine you wrote"
        case nil: return "the rules"
        default: return "the rules for finding what is open"
        }
    }

    /// One answer to "why did you do that": what was heard, who decided, what happened and how long it took.
    public var explanation: String {
        let heard = raw.isEmpty ? "nothing" : "\u{201C}\(raw)\u{201D}"
        let did = (summary?.isEmpty == false) ? " Result: \(summary ?? "")." : ""
        let seconds = String(format: "%.1f", totalMs / 1000)
        return "Heard \(heard). Decided by \(decidedBy).\(did) Took \(seconds) s."
    }
}

/// Turns a failure into a next step in plain words. Nil when there is nothing more to say than the failure itself.
public enum Recovery {
    public static func hint(for failure: String) -> String? {
        let text = failure.lowercased()
        if text.contains("not allowed to control") || text.contains("automation") {
            return "Open Settings, Permissions, and allow it."
        }
        if text.contains("accessibility") { return "Open Settings, Permissions, and allow Accessibility." }
        if text.contains("microphone") { return "Check the microphone under Settings, Permissions." }
        if text.contains("did not answer") || text.contains("not responding") {
            return "It may be busy: wait a moment and say it again."
        }
        if text.contains("quota") || text.contains("exhausted") || text.contains("429") {
            return "Hark will use the next model in Settings, Understanding."
        }
        if text.contains("offline") || text.contains("could not connect") || text.contains("network") {
            return "Check your internet connection, or turn on Keep everything on this Mac."
        }
        if text.contains("no web browser") { return "Install a web browser, then try again." }
        return nil
    }
}
