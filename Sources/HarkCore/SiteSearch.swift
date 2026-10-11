import Foundation

public struct SiteSearchRequest: Sendable, Equatable {
    /// The site as it was said ("youtube").
    public var site: String
    public var query: String
    /// The site's own search page, or a Google search limited to the site when only its address is known.
    public var address: URL?
}

/// "Open YouTube and search Imran Hashmi", "search swift concurrency on GitHub": a search that names a site is
/// run on that site, not on the default search engine. A site counts only when it is one Hark has a search page
/// for, or one that is open in a tab right now, so a word that is an app or a file never turns into a web search.
public enum SiteSearch {
    /// Search pages of common sites: addresses only, no logic. Any other open site is searched through Google
    /// limited to that site.
    private static let pages: [String: String] = [
        "youtube": "https://www.youtube.com/results?search_query=",
        "github": "https://github.com/search?q=",
        "amazon": "https://www.amazon.com/s?k=",
        "wikipedia": "https://en.wikipedia.org/w/index.php?search=",
        "reddit": "https://www.reddit.com/search/?q=",
        "stack overflow": "https://stackoverflow.com/search?q=",
        "stackoverflow": "https://stackoverflow.com/search?q=",
        "linkedin": "https://www.linkedin.com/search/results/all/?keywords=",
        "google maps": "https://www.google.com/maps/search/",
        "spotify": "https://open.spotify.com/search/",
        "imdb": "https://www.imdb.com/find/?q=",
        "npm": "https://www.npmjs.com/search?q=",
        "flipkart": "https://www.flipkart.com/search?q=",
        "ebay": "https://www.ebay.com/sch/i.html?_nkw=",
    ]
    /// Said for the plain search engine or the browser, which the web search rule already handles.
    private static let engines: Set<String> = ["google", "chrome", "web", "internet", "net", "browser", "brave", "safari"]
    private static let openers: [[String]] = [["open"], ["go", "to"], ["visit"], ["launch"], ["show"], ["on"], ["in"]]
    private static let searchWords: [[String]] = [["look", "for"], ["search", "for"], ["look", "up"], ["search"], ["find"], ["lookup"]]
    private static let joiners: Set<String> = ["and", "then"]
    private static let mostWords = 14

    /// `openHosts` are the site names (host names) open in browser tabs now.
    public static func request(in transcript: String, openHosts: [String] = []) -> SiteSearchRequest? {
        var words = tokens(transcript)
        let stems = Set(openHosts.compactMap(stem))
        func isSite(_ name: String) -> Bool {
            !engines.contains(name) && (pages[name] != nil || stems.contains(name))
        }
        while let opener = openers.first(where: { words.starts(with: $0) }), words.count > opener.count {
            words.removeFirst(opener.count)
        }
        guard words.count >= 2, words.count <= mostWords else { return nil }

        // "<site> [and] search <query>"
        for length in 1...2 where words.count > length + 1 {
            let name = words[..<length].joined(separator: " ")
            guard isSite(name) else { continue }
            var rest = Array(words[length...])
            if let first = rest.first, joiners.contains(first) { rest.removeFirst() }
            guard let trigger = searchWords.first(where: { rest.starts(with: $0) }) else { continue }
            rest.removeFirst(trigger.count)
            return make(site: name, query: rest, openHosts: openHosts)
        }
        // "search <query> on <site>"
        if let trigger = searchWords.first(where: { words.starts(with: $0) }) {
            let rest = Array(words.dropFirst(trigger.count))
            for length in [2, 1] where rest.count > length + 1 {
                let name = rest.suffix(length).joined(separator: " ")
                let lead = rest[rest.count - length - 1]
                guard ["on", "in", "at", "using"].contains(lead), isSite(name) else { continue }
                return make(site: name, query: Array(rest.dropLast(length + 1)), openHosts: openHosts)
            }
        }
        return nil
    }

    private static func make(site: String, query: [String], openHosts: [String] = []) -> SiteSearchRequest? {
        let text = query.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        var address: URL?
        if let page = pages[site] {
            address = URL(string: page + (text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text))
        } else if let host = openHosts.first(where: { stem($0) == site }) {
            var parts = URLComponents(string: "https://www.google.com/search")
            parts?.queryItems = [URLQueryItem(name: "q", value: "site:\(host) \(text)")]
            address = parts?.url
        }
        return SiteSearchRequest(site: site, query: text, address: address)
    }

    /// "www.notion.so" is "notion".
    static func stem(_ host: String) -> String? {
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
