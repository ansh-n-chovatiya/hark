import Foundation

/// One thing noticed about how the Mac is used: an app came to the front, or Chrome's front tab is
/// on a site. Only names, never a page title, address, text typed or anything copied.
public struct ActivityEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case app, site }

    public var at: Date
    public var kind: Kind
    public var name: String

    public init(at: Date, kind: Kind, name: String) {
        self.at = at
        self.kind = kind
        self.name = name
    }
}

/// The file those events are kept in, on this Mac only. Only this user may read it, and records
/// older than `keepFor` are dropped.
public final class ActivityLog: Sendable {
    public static let keepFor: TimeInterval = 90 * 24 * 60 * 60

    private let url: URL
    private let queue = DispatchQueue(label: "dev.hark.activity")

    public init(url: URL) {
        self.url = url
    }

    public func append(_ event: ActivityEvent) {
        queue.sync {
            guard var line = try? Self.encoder.encode(event) else { return }
            line.append(0x0A)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: url)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        }
    }

    public func all() -> [ActivityEvent] {
        queue.sync { read() }
    }

    /// Drops records older than 90 days. Called when Hark starts.
    public func prune(now: Date = Date()) {
        queue.sync {
            let events = read()
            let kept = events.filter { now.timeIntervalSince($0.at) <= Self.keepFor }
            guard kept.count != events.count else { return }
            write(kept)
        }
    }

    public func deleteAll() {
        queue.sync { try? FileManager.default.removeItem(at: url) }
    }

    private func read() -> [ActivityEvent] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? Self.decoder.decode(ActivityEvent.self, from: Data($0.utf8)) }
    }

    private func write(_ events: [ActivityEvent]) {
        let text = events.compactMap { try? Self.encoder.encode($0) }
            .map { String(decoding: $0, as: UTF8.self) + "\n" }.joined()
        try? text.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
