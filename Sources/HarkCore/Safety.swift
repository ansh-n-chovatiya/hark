import Foundation

/// The limits that hold whatever a model decides (see SAFETY.md).
public enum Safety {
    /// One spoken command never needs more actions than this; a model that asks for more has
    /// gone wrong.
    public static let mostActionsPerCommand = 12

    private static let searchHosts: Set<String> = ["google", "duckduckgo", "bing"]
    private static let hostFiller: Set<String> = [
        "www", "com", "org", "net", "io", "ai", "app", "dev", "co", "in", "uk", "us", "edu", "gov",
    ]

    /// True when a web address could have come from what the user said, or is one already open.
    ///
    /// A model that has read a hostile page title could otherwise be talked into opening an
    /// address that carries the user's data away in its path or query. So every part of the
    /// address has to be traceable: the site's name must be something the user said, a path may
    /// only use words they said, and a query is allowed only as a web search for words they said.
    public static func addressIsTraceable(_ address: URL, toHeard heard: String, openAddresses: [String] = []) -> Bool {
        guard let scheme = address.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = address.host()?.lowercased()
        else { return false }
        if openAddresses.contains(where: { same($0, address.absoluteString) }) { return true }

        let said = Set(normalizedWords(heard))
        let nameParts = host.split(separator: ".").map(String.init).filter { !hostFiller.contains($0) }
        let isSearch = nameParts.contains(where: searchHosts.contains)
        let isLocal = host == "localhost" || host == "127.0.0.1"
        guard isLocal || isSearch || (!nameParts.isEmpty && nameParts.allSatisfy { soundsLike(anyOf: said, $0) }) else {
            return false
        }

        let query = URLComponents(url: address, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if !query.isEmpty {
            guard isSearch, query.count == 1, query[0].name == "q" else { return false }
            return normalizedWords(query[0].value ?? "").allSatisfy(said.contains)
        }
        let pathWords = normalizedWords(address.path).filter { $0.count >= 3 }
        return isSearch ? pathWords.isEmpty || pathWords == ["search"] : pathWords.allSatisfy(said.contains)
    }

    /// True when every word of `text` is one the user said. Hark types only the user's own
    /// words, so a model cannot be talked into typing something it read elsewhere.
    public static func usesOnlyWords(said heard: String, in text: String) -> Bool {
        let said = Set(normalizedWords(heard))
        let words = normalizedWords(text)
        return !words.isEmpty && words.allSatisfy(said.contains)
    }

    private static let fileWords: Set<String> = [
        "file", "files", "folder", "folders", "directory", "project", "repo", "repository", "document",
        "script", "readme", "config", "notes", "spreadsheet", "pdf", "image", "picture",
    ]

    /// True when the user can be taken to have asked for this file or folder: they said they
    /// wanted a file, or they said most of its name. A model looking for something to open will
    /// otherwise settle for any file sharing one word with the request, such as a test file with
    /// "flow" in its name when the user asked for the app Wispr Flow.
    public static func fileWasAskedFor(_ name: String, heard: String) -> Bool {
        let said = normalizedWords(heard)
        if !fileWords.isDisjoint(with: said) { return true }
        let stem = name.split(separator: ".").first.map(String.init) ?? name
        let parts = normalizedWords(stem).filter { $0.count >= 3 }
        guard !parts.isEmpty else { return false }
        let named = parts.filter { part in said.contains { $0 == part || ($0.count >= 4 && part.hasPrefix($0)) } }
        return Double(named.count) / Double(parts.count) >= 0.6
    }

    private static func same(_ one: String, _ other: String) -> Bool {
        func trimmed(_ text: String) -> String {
            text.hasSuffix("/") ? String(text.dropLast()) : text
        }
        return trimmed(one) == trimmed(other)
    }

    /// "youtube" was said if the user said "youtube" or "you tube", allowing a letter of mishearing.
    private static func soundsLike(anyOf said: Set<String>, _ name: String) -> Bool {
        let plain = normalizedWords(name).joined()
        guard !plain.isEmpty else { return false }
        if said.contains(plain) { return true }
        let words = Array(said)
        for first in words {
            if differ(first, plain) <= (plain.count >= 6 ? 1 : 0) { return true }
            for second in words where first != second && first + second == plain { return true }
        }
        return false
    }

    private static func differ(_ one: String, _ other: String) -> Int {
        let a = Array(one), b = Array(other)
        guard abs(a.count - b.count) <= 1 else { return .max }
        var previous = Array(0...b.count)
        for row in 1...max(a.count, 1) where !a.isEmpty {
            var current = [row] + Array(repeating: 0, count: b.count)
            for column in 1...max(b.count, 1) where !b.isEmpty {
                let cost = a[row - 1] == b[column - 1] ? 0 : 1
                current[column] = min(previous[column] + 1, current[column - 1] + 1, previous[column - 1] + cost)
            }
            previous = current
        }
        return previous[b.count]
    }
}
