import Foundation

public struct FrontActionRequest: Sendable, Equatable {
    /// What was asked for, without the verb that only says "go and do it" (open, click, press).
    public var phrase: String
    /// Said as "open ..." or "click ...". Such a phrase may mean an app or a file, so it is tried against
    /// the front app only after Hark's other rules have had their say.
    public var opensSomething: Bool
}

/// A request that names no app: "new window", "print this", "open my personal DM". It is aimed at the
/// app already in front.
public enum FrontAction {
    /// Words that start commands Hark already has its own rules for. Aiming them at the front app
    /// would take them from those rules.
    private static let owned: Set<String> = [
        "close", "quit", "exit", "hide", "paste", "save", "restore", "undo", "redo", "lock", "set", "mute", "unmute",
        "arrange", "put", "move", "find", "copy", "cut", "switch", "launch", "start", "delete", "remove", "erase",
        "search", "google", "look", "type", "write", "say", "run", "stop", "volume", "turn", "pause", "play",
    ]
    private static let clickWords: Set<String> = ["click", "press", "tap", "select", "choose", "hit"]
    private static let openWords: Set<String> = ["open", "show", "go"]
    private static let politeness: [[String]] = [["please"], ["can", "you"], ["could", "you"], ["go", "ahead", "and"], ["now"]]
    private static let mostWords = 6

    public static func request(in transcript: String) -> FrontActionRequest? {
        var words = AppAction.tokens(transcript)
        var stripping = true
        while stripping {
            stripping = false
            for filler in politeness where words.starts(with: filler) && words.count > filler.count {
                words.removeFirst(filler.count)
                stripping = true
            }
        }
        guard let first = words.first, !owned.contains(first) else { return nil }
        var opens = false
        if clickWords.contains(first) {
            words.removeFirst()
            opens = true
        } else if openWords.contains(first) {
            words.removeFirst()
            if words.first == "to" { words.removeFirst() }
            opens = true
        }
        guard !words.isEmpty, words.count <= mostWords else { return nil }
        return FrontActionRequest(phrase: words.joined(separator: " "), opensSomething: opens)
    }
}
