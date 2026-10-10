import Foundation

public struct WindowMove: Sendable, Equatable {
    /// The app whose front window moves; nil is the window in front.
    public var app: String?
    public var place: WindowPlace
}

/// "Put Chrome on the left and VS Code on the right", "make this window full size", "move this to the right
/// half". Where a window goes is a short phrase with one meaning, so rules settle it. Anything with a word
/// the rules do not know is left to the rest of Hark.
public enum WindowLayout {
    private static let leads: Set<String> = ["put", "place", "move", "snap", "have", "set", "make", "send", "tile"]
    private static let fillers: Set<String> = [
        "the", "my", "a", "window", "windows", "app", "please", "half", "side", "of", "screen", "corner",
    ]
    /// Words that mean the phrase is about something else, so what is left cannot be an app's name.
    private static let notAnAppName: Set<String> = [
        "switch", "go", "open", "close", "quit", "hide", "show", "tab", "tabs", "file", "files", "folder", "folders",
        "project", "projects", "paste", "copy", "find", "next", "previous", "back", "undo", "save", "restore",
    ]
    private static let frontWords: Set<String> = ["this", "it", "current", "front", "that"]
    private static let mostWords = 14

    public static func request(in transcript: String) -> [WindowMove]? {
        var words = AppAction.tokens(transcript).filter { !["please", "can", "you", "could", "hey"].contains($0) }
        guard !words.isEmpty, words.count <= mostWords else { return nil }

        // "make this window full size", "maximise Chrome", "full screen".
        if let full = fullScreen(words) { return [full] }

        if let lead = words.first, leads.contains(lead) { words.removeFirst() }

        // "A on the left and B on the right".
        let pieces = split(words, at: "and")
        if pieces.count == 2, let first = piece(pieces[0]), let second = piece(pieces[1]) { return [first, second] }
        if pieces.count == 1, let only = piece(pieces[0]) { return [only] }
        return nil
    }

    private static func fullScreen(_ words: [String]) -> WindowMove? {
        let joined = words.joined(separator: " ")
        let triggers = ["full size", "full screen", "fullscreen", "maximize", "maximise", "fill the screen", "fill screen"]
        guard let trigger = triggers.first(where: joined.contains), words.count <= 8 else { return nil }
        // "maximise Chrome" names an app; "make this window full size" does not.
        var rest = joined.replacingOccurrences(of: trigger, with: " ").split(separator: " ").map(String.init)
        rest.removeAll { leads.contains($0) || fillers.contains($0) || frontWords.contains($0) || $0 == "to" || $0 == "size" }
        guard rest.count <= 3 else { return nil }
        return WindowMove(app: rest.isEmpty ? nil : rest.joined(separator: " "), place: .full)
    }

    /// "chrome on the left", "this window to the right half", "vs code left".
    private static func piece(_ words: [String]) -> WindowMove? {
        let sides: [([String], WindowPlace)] = [
            (["top", "left"], .topLeft), (["top", "right"], .topRight), (["bottom", "left"], .bottomLeft),
            (["bottom", "right"], .bottomRight), (["left", "third"], .leftThird), (["right", "third"], .rightThird),
            (["middle", "third"], .middleThird), (["left", "two", "thirds"], .leftTwoThirds),
            (["right", "two", "thirds"], .rightTwoThirds), (["left"], .left), (["right"], .right),
            (["top"], .top), (["bottom"], .bottom), (["centre"], .centre), (["center"], .centre),
        ]
        for (place, value) in sides {
            guard let range = find(place, in: words) else { continue }
            var rest = Array(words[..<range.lowerBound]) + Array(words[range.upperBound...])
            rest.removeAll { $0 == "on" || $0 == "to" || $0 == "in" || $0 == "at" }
            rest.removeAll { fillers.contains($0) }
            if rest.allSatisfy({ frontWords.contains($0) }) { return WindowMove(app: nil, place: value) }
            guard rest.count <= 3, !rest.contains(where: { frontWords.contains($0) || notAnAppName.contains($0) }) else {
                return nil
            }
            return WindowMove(app: rest.joined(separator: " "), place: value)
        }
        return nil
    }

    private static func find(_ run: [String], in words: [String]) -> Range<Int>? {
        guard words.count >= run.count else { return nil }
        for start in 0...(words.count - run.count) where Array(words[start..<(start + run.count)]) == run {
            return start..<(start + run.count)
        }
        return nil
    }

    private static func split(_ words: [String], at separator: String) -> [[String]] {
        var parts: [[String]] = [[]]
        for word in words {
            if word == separator { parts.append([]) } else { parts[parts.count - 1].append(word) }
        }
        return parts.filter { !$0.isEmpty }
    }
}
