import Foundation

/// Where "open X in a new tab" should go: a site when X looks like one, otherwise a web search.
/// Nil means a blank tab.
public func webAddress(for words: String) -> URL? {
    let text = words.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !text.isEmpty else { return nil }
    if text.hasPrefix("http://") || text.hasPrefix("https://") { return URL(string: text) }
    if !text.contains(" ") {
        if text == "localhost" || text.hasPrefix("localhost:") { return URL(string: "http://\(text)") }
        return URL(string: text.contains(".") ? "https://\(text)" : "https://www.\(text).com")
    }
    var search = URLComponents(string: "https://www.google.com/search")
    search?.queryItems = [URLQueryItem(name: "q", value: text)]
    return search?.url
}
