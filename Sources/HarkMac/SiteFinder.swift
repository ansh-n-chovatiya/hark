import Foundation
import HarkCore

/// Finds where a site's own search page is, from the site itself: its home page names an OpenSearch description,
/// and that holds the address. Nothing is listed in advance, so a site Hark has never seen works too. What was found
/// is kept in ~/.config/hark/site-search.json, so a site is looked up once.
actor SiteFinder {
    static let shared = SiteFinder()

    private struct Entry: Codable { var host: String; var template: String? }
    private var cache: [String: Entry]
    private let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/hark/site-search.json")
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        session = URLSession(configuration: configuration)
        cache = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    /// The search page for `query` on the site called `name`. A site open in a tab (`openHosts`) is always
    /// searchable, through Google limited to it when it publishes no search page of its own. A site that is not
    /// open must publish one, so a word that is only a name ("finder", "pune") never becomes a web search.
    func address(for name: String, query: String, openHosts: [String]) async -> URL? {
        let key = name.lowercased()
        let open = openHosts.first { SiteSearch.stem($0) == key.replacingOccurrences(of: " ", with: "") }
        let entry: Entry
        if let known = cache[key] {
            entry = known
        } else {
            let host = open ?? "www.\(key.replacingOccurrences(of: " ", with: "")).com"
            entry = Entry(host: host, template: await template(onHost: host))
            // A guess that found nothing is not worth keeping: the site may simply not exist.
            if entry.template != nil || open != nil { cache[key] = entry; save() }
        }
        if let template = entry.template, let url = OpenSearch.address(template: template, query: query) { return url }
        return open == nil ? nil : SiteSearch.limitedToSite(open ?? entry.host, query: query)
    }

    private func template(onHost host: String) async -> String? {
        guard let home = URL(string: "https://\(host)/") else { return nil }
        guard let html = await text(of: home), let link = OpenSearch.descriptionLink(inHTML: html, base: home) else { return nil }
        guard let xml = await text(of: link) else { return nil }
        return OpenSearch.template(inXML: xml)
    }

    private func text(of url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh) Hark", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return String(decoding: data.prefix(2_000_000), as: UTF8.self)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
