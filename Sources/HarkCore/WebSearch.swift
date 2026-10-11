import Foundation

public struct WebSearchRequest: Sendable, Equatable {
    public var query: String
    /// The browser the user named ("open Brave and search ..."), as said, so the search opens there. Nil when none.
    public var browser: String?

    public var address: URL? {
        var parts = URLComponents(string: "https://www.google.com/search")
        parts?.queryItems = [URLQueryItem(name: "q", value: query)]
        return parts?.url
    }
}

/// Recognises "search X on Google", "google X", "look up X" and "open <browser> and search X" by rule, so
/// a web search does not need a model. The search is built only from the words that were said. Phrases
/// that are about files or folders, or that name nothing to search for, are left to the rest of Hark.
public enum WebSearch {
    private static let triggers: [[String]] = [["search", "for"], ["search"], ["google"], ["look", "up"], ["lookup"]]
    private static let browserOpeners: Set<String> = ["open", "launch", "start"]
    private static let webEndings: [[String]] = [
        ["on", "the", "google"], ["on", "google"], ["in", "google"], ["using", "google"], ["with", "google"],
        ["on", "the", "web"], ["on", "the", "internet"], ["on", "the", "net"], ["online"],
        ["in", "a", "new", "tab"], ["in", "new", "tab"],
    ]
    private static let browserLeads: Set<String> = ["in", "on", "using", "with", "the"]
    private static let fileWords: Set<String> = [
        "file", "files", "folder", "folders", "directory", "document", "documents", "project", "projects",
        "finder", "downloads", "desktop", "mac", "computer", "disk", "drive", "repo", "repository",
    ]
    private static let empty: Set<String> = ["something", "anything", "stuff", "it", "this", "that", "things", "random"]
    private static let mostWords = 12

    /// `browserWords` are the words that can name a browser on this Mac ("browser", "brave", "chrome"), so no browser
    /// is known to the rule itself.
    public static func request(in transcript: String, browserWords: Set<String> = ["browser"]) -> WebSearchRequest? {
        var words = tokens(transcript)
        var browser: String?
        var webContext = false

        // "Open <browser> and ..." in front.
        if let first = words.first, browserOpeners.contains(first) {
            var index = 1
            if words.indices.contains(index), words[index] == "the" { index += 1 }
            var named: [String] = []
            // "google chrome": the engine's name in front of a browser's name belongs to the name.
            func partOfName(_ at: Int) -> Bool {
                guard words.indices.contains(at) else { return false }
                return browserWords.contains(words[at]) || (words[at] == "google" && words.indices.contains(at + 1) && browserWords.contains(words[at + 1]))
            }
            while partOfName(index) {
                named.append(words[index])
                index += 1
            }
            if named.contains(where: browserWords.contains) {
                words.removeFirst(index)
                if words.first == "and" || words.first == "then" { words.removeFirst() }
                browser = named.joined(separator: " ")
                webContext = true
            }
        }
        guard let trigger = triggers.first(where: { words.starts(with: $0) }) else { return nil }
        words.removeFirst(trigger.count)
        if trigger == ["google"] || trigger == ["look", "up"] || trigger == ["lookup"] { webContext = true }

        // "... in Brave", "... in the browser" at the end.
        var tail = words.count
        while tail > 0, browserWords.contains(words[tail - 1]) || words[tail - 1] == "google" { tail -= 1 }
        if tail < words.count, tail > 0, browserLeads.contains(words[tail - 1]),
           words[tail...].contains(where: browserWords.contains) {
            browser = browser ?? words[tail...].joined(separator: " ")
            var cut = tail - 1
            if words[cut] == "the", cut > 0, browserLeads.contains(words[cut - 1]) { cut -= 1 }
            words.removeSubrange(cut...)
            webContext = true
        }

        // "... on Google" at the end.
        var stripped = true
        while stripped {
            stripped = false
            for ending in webEndings where words.count > ending.count && Array(words.suffix(ending.count)) == ending {
                words.removeLast(ending.count)
                webContext = true
                stripped = true
            }
        }

        guard !words.isEmpty, words.count <= mostWords, !words.allSatisfy({ empty.contains($0) }) else { return nil }
        if !webContext, !words.filter(fileWords.contains).isEmpty { return nil }
        // "Search for the files in my project" is about files even with a web word elsewhere.
        if words.contains(where: { ["file", "files", "folder", "folders"].contains($0) }) { return nil }
        return WebSearchRequest(query: words.joined(separator: " "), browser: browser)
    }

    private static func tokens(_ text: String) -> [String] {
        let cleaned = text.lowercased().map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }
        return String(cleaned).split(separator: " ").map(String.init)
    }
}
