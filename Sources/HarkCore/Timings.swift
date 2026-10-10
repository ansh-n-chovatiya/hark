import Foundation

public struct Timings: Codable, Sendable, Equatable {
    public var at: Date
    public var raw: String
    public var verb: String?
    public var outcome: String
    public var transcribeMs: Double
    public var parseMs: Double
    public var matchMs: Double
    public var actMs: Double
    public var totalMs: Double
    /// Time spent asking the local model; nil when the rules decided alone.
    public var modelMs: Double?
    /// The tools the model called, in order; nil when the rules decided alone.
    public var tools: [String]?
    /// What Hark did or said in reply, as shown to the user. Never holds clipboard text.
    public var summary: String?
    /// Which model answered, when one was asked: "Online model", "Claude Code", "Model on this Mac".
    public var model: String?

    public init(
        at: Date,
        raw: String,
        verb: String?,
        outcome: String,
        transcribeMs: Double,
        parseMs: Double,
        matchMs: Double,
        actMs: Double,
        totalMs: Double,
        modelMs: Double? = nil,
        tools: [String]? = nil,
        summary: String? = nil,
        model: String? = nil
    ) {
        self.at = at
        self.raw = raw
        self.verb = verb
        self.outcome = outcome
        self.transcribeMs = transcribeMs
        self.parseMs = parseMs
        self.matchMs = matchMs
        self.actMs = actMs
        self.totalMs = totalMs
        self.modelMs = modelMs
        self.tools = tools
        self.summary = summary
        self.model = model
    }
}

public final class TimingLog: Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "dev.hark.timings")

    public init(url: URL) {
        self.url = url
    }

    public func append(_ timings: Timings) {
        queue.async { [url] in
            do {
                var line = try Self.encoder.encode(timings)
                line.append(0x0A)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                } else {
                    try line.write(to: url)
                }
            } catch {
                FileHandle.standardError.write(Data("hark: could not write timing log: \(error)\n".utf8))
            }
        }
    }

    /// Keeps the newest `maxEntries` entries and drops the rest, so the file does not grow for ever.
    /// Called when Hark starts.
    public func trim(keeping maxEntries: Int = 5000) {
        queue.sync {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            guard lines.count > maxEntries else { return }
            let kept = lines.suffix(maxEntries).joined(separator: "\n") + "\n"
            try? kept.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func all() -> [Timings] {
        queue.sync {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap {
                try? Self.decoder.decode(Timings.self, from: Data($0.utf8))
            }
        }
    }

    public func medianTotalMs(verb: String) -> Double? {
        median(all().filter { $0.verb == verb }.map(\.totalMs))
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}
