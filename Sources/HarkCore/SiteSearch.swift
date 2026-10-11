import Foundation

public struct SiteSearchRequest: Sendable, Equatable {
    /// The site as it was said ("youtube"). Whether it is a site at all is decided by looking it up.
    public var site: String
    public var query: String
}

/// "Open YouTube and search Imran Hashmi", "search swift concurrency on GitHub": a search that names a place is
/// run in that place, not on the default search engine. Nothing here knows any particular site: the words only say
/// "this name, this query", and the site's own published search page is looked up afterwards (see `OpenSearch`).
public enum SiteSearch {
    /// Said for the plain search engine or the web itself, which the web search rule already handles. A browser's
    /// name is added by the caller (`browserWords`).
    private static let engines: Set<String> = ["google", "web", "internet", "net"]
    private static let openers: [[String]] = [["open"], ["go", "to"], ["visit"], ["launch"], ["show"]]
    private static let searchWords: [[String]] = [["look", "for"], ["search", "for"], ["look", "up"], ["search"], ["find"], ["lookup"]]
    private static let joiners: Set<String> = ["and", "then"]
    private static let mostWords = 14

    public static func request(in transcript: String, browserWords: Set<String> = ["browser"]) -> SiteSearchRequest? {
        let engines = Self.engines.union(browserWords)
        var words = tokens(transcript)
        var opened = false
        while let opener = openers.first(where: { words.starts(with: $0) }), words.count > opener.count {
            words.removeFirst(opener.count)
            opened = true
        }
        guard words.count >= 3, words.count <= mostWords else { return nil }

        // "open <name> [and] search <query>": only after an opener, so a plain "search ..." stays a web search.
        if opened {
            for length in 1...2 where words.count > length + 1 {
                let name = Array(words[..<length])
                guard !engines.contains(name.joined(separator: " ")), name.allSatisfy({ !joinersAndSearch.contains($0) }) else { continue }
                var rest = Array(words[length...])
                if let first = rest.first, joiners.contains(first) { rest.removeFirst() }
                guard let trigger = searchWords.first(where: { rest.starts(with: $0) }) else { continue }
                rest.removeFirst(trigger.count)
                return make(site: name.joined(separator: " "), query: rest)
            }
        }
        // "search <query> on <name>"
        if let trigger = searchWords.first(where: { words.starts(with: $0) }) {
            let rest = Array(words.dropFirst(trigger.count))
            for length in [2, 1] where rest.count > length + 1 {
                let name = rest.suffix(length).joined(separator: " ")
                let lead = rest[rest.count - length - 1]
                guard ["on", "in", "at", "using"].contains(lead), !engines.contains(name) else { continue }
                return make(site: name, query: Array(rest.dropLast(length + 1)))
            }
        }
        return nil
    }

    private static let joinersAndSearch: Set<String> = joiners.union(["search", "find", "look", "lookup"])

    private static func make(site: String, query: [String]) -> SiteSearchRequest? {
        let text = query.joined(separator: " ")
        return text.isEmpty ? nil : SiteSearchRequest(site: site, query: text)
    }

    /// For a site that is open but publishes no search page: a Google search limited to that site.
    public static func limitedToSite(_ host: String, query: String) -> URL? {
        var parts = URLComponents(string: "https://www.google.com/search")
        parts?.queryItems = [URLQueryItem(name: "q", value: "site:\(host) \(query)")]
        return parts?.url
    }

    /// "www.notion.so" is "notion"; "youtube.com" is "youtube".
    public static func stem(_ host: String) -> String? {
        var labels = host.lowercased().split(separator: ".").map(String.init)
        if labels.first == "www" { labels.removeFirst() }
        guard labels.count >= 2 else { return labels.first }
        return labels[labels.count - 2]
    }

    private static func tokens(_ text: String) -> [String] {
        let cleaned = text.lowercased().map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }
        return String(cleaned).split(separator: " ").map(String.init)
    }
}

/// How a site says where its own search is: the standard OpenSearch description. A page names it in a
/// `<link rel="search">`, and the description holds the address with `{searchTerms}` where the words go.
public enum OpenSearch {
    /// The address of the description, from a page's HTML.
    public static func descriptionLink(inHTML html: String, base: URL) -> URL? {
        for tag in matches(#"<link\b[^>]*>"#, in: html) {
            guard tag.lowercased().contains("opensearchdescription"), let href = attribute("href", in: tag), !href.isEmpty
            else { continue }
            return URL(string: href, relativeTo: base)?.absoluteURL
        }
        return nil
    }

    /// The page template from a description: the HTML `<Url>` that holds `{searchTerms}`.
    public static func template(inXML xml: String) -> String? {
        var fallback: String?
        for tag in matches(#"<Url\b[^>]*>"#, in: xml) {
            guard let template = attribute("template", in: tag)?.replacingOccurrences(of: "&amp;", with: "&"),
                  template.contains("{searchTerms}")
            else { continue }
            let type = attribute("type", in: tag)?.lowercased() ?? ""
            if type.hasPrefix("text/html") || type.hasPrefix("application/xhtml") { return template }
            if type.isEmpty { fallback = fallback ?? template }
        }
        return fallback
    }

    /// The template with the words in place; optional parts such as `{language?}` are dropped.
    public static func address(template: String, query: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#"))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        var text = template.replacingOccurrences(of: "{searchTerms}", with: encoded)
        text = text.replacingOccurrences(of: #"\{[^}]*\?\}"#, with: "", options: .regularExpression)
        // A part left empty ("&page=") is dropped.
        text = text.replacingOccurrences(of: #"&[^&=#]+=(?=&|#|$)"#, with: "", options: .regularExpression)
        guard !text.contains("{"), let url = URL(string: text), url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let found = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag))
        else { return nil }
        for group in 1...2 {
            if let range = Range(found.range(at: group), in: tag) { return String(tag[range]) }
        }
        return nil
    }
}
