import Foundation

/// Web pages the user has given a name to, so "open the backend logs" needs no searching.
public enum Links {
    /// The saved link whose name is what was asked for, ignoring case, punctuation and small words.
    public static func find(_ query: String, in links: [String: String]) -> (name: String, address: URL)? {
        let wanted = significantWords(query)
        guard !wanted.isEmpty else { return nil }
        for (name, address) in links.sorted(by: { $0.key < $1.key }) where significantWords(name) == wanted {
            guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            return (name, url)
        }
        return nil
    }

    private static func significantWords(_ text: String) -> [String] {
        normalizedWords(text).filter { !["the", "a", "an", "my", "page", "link", "site"].contains($0) }
    }
}

/// Spotting "... and tell me when it finishes", which asks for a routine to run on its own while
/// the user gets on with something else.
public enum Background {
    private static let markers: [[String]] = [
        ["tell", "me", "when"], ["let", "me", "know", "when"], ["notify", "me", "when"],
        ["in", "the", "background"], ["in", "background"],
    ]

    private static let leadIns: Set<String> = ["in", "into", "the", "put", "button", "it", "to", "and", "then", "keep"]

    /// The command without the request to be told, and whether that request was there.
    public static func split(_ transcript: String) -> (command: String, inBackground: Bool) {
        let words = normalizedWords(transcript)
        // The recogniser sometimes writes "put in" as something else ("button background"), so the
        // word itself is enough once the words leading up to it are set aside.
        if let named = words.firstIndex(of: "background"), !markers.contains(where: { m in
            words.indices.contains { words[$0...].starts(with: m) }
        }) {
            var start = named
            while start > 0, leadIns.contains(words[start - 1]) { start -= 1 }
            return (words[..<start].joined(separator: " "), true)
        }
        for start in words.indices {
            guard markers.contains(where: { words[start...].starts(with: $0) }) else { continue }
            var kept = Array(words[..<start])
            // "Open it and put it in the background" leaves joining words behind once the request is cut off.
            while let last = kept.last, ["and", "then", "put", "it", "keep", "but"].contains(last) { kept.removeLast() }
            return (kept.joined(separator: " "), true)
        }
        return (transcript, false)
    }
}

/// Commands the user marked as having gone wrong, kept so they can become test cases.
public final class WrongLog: Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public var at: Date
        public var heard: String
        public var did: String
        public var wanted: String

        public init(at: Date, heard: String, did: String, wanted: String) {
            self.at = at
            self.heard = heard
            self.did = did
            self.wanted = wanted
        }
    }

    private let url: URL
    private let queue = DispatchQueue(label: "dev.hark.wrong")

    public init(url: URL) {
        self.url = url
    }

    public func append(_ entry: Entry) {
        queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard var line = try? encoder.encode(entry) else { return }
            line.append(0x0A)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: url)
            }
        }
    }

    public func all() -> [Entry] {
        queue.sync {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
        }
    }
}
