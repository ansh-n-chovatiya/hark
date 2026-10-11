import Foundation
import HarkCore

/// A fixed set of spoken commands with what should happen, run against a made-up desk, so that
/// "is Hark getting better?" has a number for an answer.
public struct Evaluation: Codable, Sendable {
    public struct Thing: Codable, Sendable {
        var kind: ItemKind
        var title: String
        var detail: String?
        var owner: String?
        var running: Bool?
        var folder: Bool?
        var front: Bool?
    }

    public struct Case: Codable, Sendable {
        var say: String
        /// "done", "confirm", "refuse" or "nothing".
        var expect: String
        /// Words that must appear in what Hark reports it would do.
        var mentions: [String]?
        /// Words that must not appear.
        var avoids: [String]?
    }

    public struct Result: Sendable {
        public let say: String
        public let passed: Bool
        public let got: String
        public let seconds: Double
    }

    var desk: [Thing]
    var folders: [String]
    /// The apps installed on the made-up Mac, as the name on disk and the app's own name ("Visual Studio Code" and
    /// "Code"), from which the other ways to say a name are worked out.
    var installedApps: [InstalledName]?
    struct InstalledName: Codable, Sendable { var folderName: String; var shortName: String }
    /// Saved web pages by name, for cases about opening one.
    var links: [String: String]?
    var cases: [Case]

    public static func load(from url: URL) throws -> Evaluation {
        try JSONDecoder().decode(Evaluation.self, from: Data(contentsOf: url))
    }

    /// Runs every case through a dry-run pipeline. `pause` spaces the cases out for a rate limit.
    public func run(
        config: Config, pause: Duration, progress: @Sendable (Result) -> Void
    ) async -> [Result] {
        AppNames.pretended = installedApps.map { apps in
            apps.map { InstalledApp(
                url: URL(fileURLWithPath: "/Applications/\($0.folderName).app"), bundleID: nil, folderName: $0.folderName,
                shortName: $0.shortName, category: nil, opensFolders: false, runsPrograms: false) }
        }
        defer { AppNames.pretended = nil }
        var settings = config
        settings.searchFolders = folders
        settings.repos = []
        settings.aliases = [:]
        settings.routines = []
        settings.links = links ?? [:]
        let scratch = FileManager.default.temporaryDirectory.appending(path: "hark-evaluation.jsonl")
        let clock = ContinuousClock()
        var results: [Result] = []
        for (index, test) in cases.enumerated() {
            if index > 0 { try? await Task.sleep(for: pause) }
            let pipeline = Pipeline(
                config: settings, sources: [FixedDesk(desk)], log: TimingLog(url: scratch), dryRun: true)
            let started = clock.now
            let outcome = await pipeline.run(transcript: test.say, transcribeMs: 0)
            let elapsed = clock.now - started
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            let result = Result(
                say: test.say, passed: Self.passes(outcome, test), got: Self.text(of: outcome), seconds: seconds)
            progress(result)
            results.append(result)
        }
        return results
    }

    private static func passes(_ outcome: Outcome, _ test: Case) -> Bool {
        let got = text(of: outcome).lowercased()
        let kind: String
        switch outcome {
        case .done(let text), .answer(let text): kind = text.hasPrefix("Would") ? "done" : "nothing"
        case .confirm: kind = "confirm"
        case .failed(let text): kind = text.contains("does not delete") ? "refuse" : "nothing"
        case .choose, .notUnderstood: kind = "nothing"
        }
        guard kind == test.expect else { return false }
        return (test.mentions ?? []).allSatisfy { got.contains($0.lowercased()) }
            && !(test.avoids ?? []).contains { got.contains($0.lowercased()) }
    }

    private static func text(of outcome: Outcome) -> String {
        switch outcome {
        case .done(let text), .confirm(let text), .notUnderstood(let text), .failed(let text), .answer(let text): text
        case .choose(let matches): "list: " + matches.map(\.item.title).joined(separator: ", ")
        }
    }
}

/// A source that always answers with the same made-up items and changes nothing.
private struct FixedDesk: ItemSource {
    let kinds: Set<ItemKind>
    private let items: [Item]

    init(_ things: [Evaluation.Thing]) {
        items = things.enumerated().map { index, thing in
            var payload: [String: String] = [:]
            if thing.kind == .app, thing.running ?? true { payload["pid"] = "\(1000 + index)" }
            if thing.kind == .file {
                payload["path"] = "/evaluation/\(thing.detail ?? "")/\(thing.title)"
                payload["folder"] = thing.folder == true ? "yes" : "no"
            }
            return Item(
                id: "\(thing.kind.rawValue):\(index)", kind: thing.kind, title: thing.title,
                detail: thing.detail ?? "", owner: thing.owner ?? "",
                lastUsed: thing.front == true ? Date() : nil, payload: payload)
        }
        kinds = Set(items.map(\.kind))
    }

    func refresh() async {}

    func items(for command: Command) async -> [Item] { items }

    func perform(_ verb: Verb, on item: Item) async throws -> UndoStep? { nil }
}
