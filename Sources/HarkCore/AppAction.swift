import Foundation

public struct AppActionRequest: Sendable, Equatable {
    public var app: String
    public var action: String
}

/// "Open Notes and create a new note": open an app, then do something in it. The app lists what it
/// can do in its own menu bar, so the words after "and" are matched against those menu items, with
/// no model. A match is used only when one item clearly fits.
public enum AppAction {
    private static let starts: [[String]] = [["open"], ["launch"], ["start"], ["switch", "to"], ["go", "to"]]
    private static let joiners: Set<String> = ["and", "then"]
    private static let fluff: Set<String> = ["please", "now", "just", "i", "want", "to", "want to", "do", "and", "then"]
    private static let mostWords = 8

    public static func request(in transcript: String) -> AppActionRequest? {
        var words = tokens(transcript)
        guard let start = starts.first(where: { words.starts(with: $0) }) else { return nil }
        words.removeFirst(start.count)
        guard let split = words.firstIndex(where: joiners.contains), split >= 1, split <= 3 else { return nil }
        var app = Array(words[..<split])
        if app.last == "app" || app.last == "application" { app.removeLast() }
        var action = Array(words[(split + 1)...])
        while let first = action.first, fluff.contains(first) { action.removeFirst() }
        guard !app.isEmpty, !action.isEmpty, action.count <= mostWords else { return nil }
        return AppActionRequest(app: app.joined(separator: " "), action: action.joined(separator: " "))
    }

    public struct Ranked: Sendable, Equatable {
        public var path: [String]
        public var score: Double
        public var title: String { path.last ?? "" }
    }

    public enum Choice: Sendable, Equatable {
        case item([String])
        /// Two or more fit about equally well.
        case unsure([[String]])
        case none
    }

    /// Words that mean "new": people say "create a note", menus say "New Note".
    private static let asNew: Set<String> = ["create", "make", "add", "start", "begin", "compose", "write"]
    private static let dropped: Set<String> = ["a", "an", "the", "one", "please", "this", "my", "in", "it", "on", "me"]
    private static let quietMenus: Set<String> = ["window", "help"]
    private static let minimum = 0.6
    /// Smaller than the 0.08 lost for each extra word, so a title one word shorter always wins, while
    /// two titles equally close stay unsure.
    private static let margin = 0.07

    public static func choose(_ phrase: String, among paths: [[String]]) -> Choice {
        let ranked = rank(phrase, among: paths)
        guard let best = ranked.first, best.score >= minimum else { return .none }
        let close = ranked.filter { best.score - $0.score < margin && $0.title.lowercased() != best.title.lowercased() }
        return close.isEmpty ? .item(best.path) : .unsure(([best] + close).prefix(3).map(\.path))
    }

    /// The one menu item whose title is what was said, ignoring "a", "the" and "this", or nil. Used when
    /// the words name no app, so it has to be sure.
    public static func exact(_ phrase: String, among paths: [[String]]) -> [String]? {
        let ranked = rank(phrase, among: paths)
        guard let best = ranked.first, best.score >= 0.95 else { return nil }
        return ranked.dropFirst().contains { $0.score >= 0.95 } ? nil : best.path
    }

    public enum LabelChoice: Sendable, Equatable {
        case label(Int)
        case unsure([Int])
        case none
    }

    /// Which of these labels (the words on buttons, tabs and list items) was meant. Several labels
    /// fitting about equally is "unsure", never a guess.
    public static func chooseLabel(_ phrase: String, among labels: [String]) -> LabelChoice {
        let paths = labels.map { ["control", $0] }
        switch choose(phrase, among: paths) {
        case .none: return .none
        case .item(let path): return labels.firstIndex(of: path[1]).map(LabelChoice.label) ?? .none
        case .unsure(let options):
            let indexes = options.compactMap { option in labels.firstIndex(of: option[1]) }
            return indexes.count > 1 ? .unsure(indexes) : (indexes.first.map(LabelChoice.label) ?? .none)
        }
    }

    public static func rank(_ phrase: String, among paths: [[String]]) -> [Ranked] {
        let wanted = canonical(tokens(phrase))
        guard !wanted.isEmpty else { return [] }
        var best: [String: Ranked] = [:]
        // The system's Services menu lists other apps' commands, not this app's.
        for path in paths where path.count >= 2 && !path.contains("Services") {
            let have = canonical(tokens(path[path.count - 1]))
            guard !have.isEmpty else { continue }
            var score = fit(wanted, have)
            guard score > 0 else { continue }
            if quietMenus.contains(path[0].lowercased()) { score -= 0.15 }
            let key = path[path.count - 1].lowercased()
            if let existing = best[key], existing.score >= score { continue }
            best[key] = Ranked(path: path, score: score)
        }
        return best.values.sorted { ($0.score, -Double($0.title.count)) > ($1.score, -Double($1.title.count)) }
    }

    private static func fit(_ wanted: [String], _ have: [String]) -> Double {
        let wantedSet = Set(wanted), haveSet = Set(have)
        if wantedSet == haveSet { return 1.0 }
        let shared = wantedSet.intersection(haveSet).count
        guard shared > 0 else { return 0 }
        // Everything asked for is in the title, which has a few extra words ("New Note" in "New Note in Folder").
        if wantedSet.isSubset(of: haveSet) { return max(0.6, 0.9 - 0.08 * Double(haveSet.count - wantedSet.count)) }
        // The title is shorter than the request ("print this page" for "Print").
        if haveSet.isSubset(of: wantedSet) { return haveSet.count == 1 ? 0.65 : 0.75 }
        return 0.5 * Double(shared) / Double(wantedSet.count)
    }

    private static func canonical(_ words: [String]) -> [String] {
        var result: [String] = []
        for word in words where !dropped.contains(word) {
            let mapped = asNew.contains(word) ? "new" : word
            if result.last != mapped { result.append(mapped) }
        }
        return result
    }

    public static func tokens(_ text: String) -> [String] {
        let cleaned = text.lowercased().map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }
        return String(cleaned).split(separator: " ").map(String.init)
    }
}
