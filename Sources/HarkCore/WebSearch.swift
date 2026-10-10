import Foundation

public struct WebSearchRequest: Sendable, Equatable {
    public var query: String
    /// The user named Chrome ("open Chrome and search ..."), so the search opens there.
    public var inChrome: Bool

    public var address: URL? {
        var parts = URLComponents(string: "https://www.google.com/search")
        parts?.queryItems = [URLQueryItem(name: "q", value: query)]
        return parts?.url
    }
}

/// Recognises "search X on Google", "google X", "look up X" and "open Chrome and search X" by rule, so
/// a web search does not need a model. The search is built only from the words that were said. Phrases
/// that are about files or folders, or that name nothing to search for, are left to the rest of Hark.
public enum WebSearch {
    private static let triggers: [[String]] = [["search", "for"], ["search"], ["google"], ["look", "up"], ["lookup"]]
    private static let browserStarts: [[String]] = [
        ["open", "google", "chrome"], ["open", "chrome"], ["launch", "chrome"], ["start", "chrome"],
        ["open", "the", "browser"], ["open", "browser"],
    ]
    private static let webEndings: [[String]] = [
        ["on", "the", "google"], ["on", "google"], ["in", "google"], ["using", "google"], ["with", "google"],
        ["on", "the", "web"], ["on", "the", "internet"], ["on", "the", "net"], ["online"],
        ["in", "chrome"], ["on", "chrome"], ["in", "a", "new", "tab"], ["in", "new", "tab"], ["in", "the", "browser"],
    ]
    private static let fileWords: Set<String> = [
        "file", "files", "folder", "folders", "directory", "document", "documents", "project", "projects",
        "finder", "downloads", "desktop", "mac", "computer", "disk", "drive", "repo", "repository",
    ]
    private static let empty: Set<String> = ["something", "anything", "stuff", "it", "this", "that", "things", "random"]
    private static let mostWords = 12

    public static func request(in transcript: String) -> WebSearchRequest? {
        var words = tokens(transcript)
        var inChrome = false
        var webContext = false

        // "Open Chrome and ..." in front.
        for start in browserStarts where words.starts(with: start) {
            words.removeFirst(start.count)
            if words.first == "and" || words.first == "then" { words.removeFirst() }
            inChrome = start.contains("chrome")
            webContext = true
            break
        }
        guard let trigger = triggers.first(where: { words.starts(with: $0) }) else { return nil }
        words.removeFirst(trigger.count)
        if trigger == ["google"] || trigger == ["look", "up"] || trigger == ["lookup"] { webContext = true }

        // "... on Google" at the end.
        var stripped = true
        while stripped {
            stripped = false
            for ending in webEndings where words.count > ending.count && Array(words.suffix(ending.count)) == ending {
                words.removeLast(ending.count)
                webContext = true
                inChrome = inChrome || ending.contains("chrome")
                stripped = true
            }
        }

        guard !words.isEmpty, words.count <= mostWords, !words.allSatisfy({ empty.contains($0) }) else { return nil }
        if !webContext, !words.filter(fileWords.contains).isEmpty { return nil }
        // "Search for the files in my project" is about files even with a web word elsewhere.
        if words.contains(where: { ["file", "files", "folder", "folders"].contains($0) }) { return nil }
        return WebSearchRequest(query: words.joined(separator: " "), inChrome: inChrome)
    }

    private static func tokens(_ text: String) -> [String] {
        let cleaned = text.lowercased().map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }
        return String(cleaned).split(separator: " ").map(String.init)
    }
}
