import Foundation

/// What Hark remembers about suggestions: which were dismissed or accepted, and whether the first-run
/// setup has happened.
public struct LearningState: Codable, Sendable, Equatable {
    public struct Accepted: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var kind: Suggestion.Kind
        public var title: String
        public var at: Date
        /// What accepting added, so removing takes back exactly that.
        public var aliasKey: String?
        public var aliasValue: String?
        public var links: [String: String]
        public var routineName: String?

        public init(
            id: String, kind: Suggestion.Kind, title: String, at: Date, aliasKey: String? = nil,
            aliasValue: String? = nil, links: [String: String] = [:], routineName: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.at = at
            self.aliasKey = aliasKey
            self.aliasValue = aliasValue
            self.links = links
            self.routineName = routineName
        }
    }

    public var setupDone = false
    /// Suggestion id to the time it may be offered again; `distantFuture` means never.
    public var hidden: [String: Date] = [:]
    public var accepted: [Accepted] = []
    /// Names a model proposed for failed commands, kept only after a dry run showed they work.
    public var reviewed: [Suggestion] = []
    public var lastReviewAt: Date?

    public init() {}

    // A file from an older version may lack the newer fields; each missing one stays at its default.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        setupDone = try values.decodeIfPresent(Bool.self, forKey: .setupDone) ?? false
        hidden = try values.decodeIfPresent([String: Date].self, forKey: .hidden) ?? [:]
        accepted = try values.decodeIfPresent([Accepted].self, forKey: .accepted) ?? []
        reviewed = try values.decodeIfPresent([Suggestion].self, forKey: .reviewed) ?? []
        lastReviewAt = try values.decodeIfPresent(Date.self, forKey: .lastReviewAt)
    }
}

public final class LearningStore: Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "dev.hark.learning")

    public init(url: URL) {
        self.url = url
    }

    public func load() -> LearningState {
        queue.sync { read() }
    }

    public func change(_ edit: (inout LearningState) -> Void) {
        queue.sync {
            var state = read()
            edit(&state)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(state) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    public func erase() {
        queue.sync { try? FileManager.default.removeItem(at: url) }
    }

    private func read() -> LearningState {
        guard let data = try? Data(contentsOf: url) else { return LearningState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(LearningState.self, from: data)) ?? LearningState()
    }
}

public struct LearningSnapshot: Sendable, Equatable {
    public var suggestions: [Suggestion]
    public var deadEnds: [DeadEnd]
    public var accepted: [LearningState.Accepted]

    public init(suggestions: [Suggestion] = [], deadEnds: [DeadEnd] = [], accepted: [LearningState.Accepted] = []) {
        self.suggestions = suggestions
        self.deadEnds = deadEnds
        self.accepted = accepted
    }
}

/// Ties the log, the history and the remembered choices together. Accepting a suggestion edits the
/// config the user already has (aliases, saved pages, routines), so everything can still be seen and
/// changed in the usual screens.
public final class LearningCenter: Sendable {
    public static let notNowFor: TimeInterval = 14 * 24 * 60 * 60

    /// How long after a review before the next one.
    public static let reviewEvery: TimeInterval = 6 * 60 * 60
    private static let mostToReview = 12

    public let activity: ActivityLog
    private let history: TimingLog
    private let store: LearningStore
    private let reports: WrongLog?

    public init(activity: ActivityLog, history: TimingLog, store: LearningStore, reports: WrongLog? = nil) {
        self.activity = activity
        self.history = history
        self.store = store
        self.reports = reports
    }

    public func snapshot(config: Config, now: Date = Date()) -> LearningSnapshot {
        let state = store.load()
        let historyEntries = history.all()
        let known = Set(config.aliases.keys.map(Learner.normalize))
        let made = config.learns
            ? Learner.unique(
                Learner.suggestions(history: historyEntries, activity: activity.all(), config: config)
                    + Learner.names(reports: reports?.all() ?? [], config: config)
                    + state.reviewed.filter { !known.contains($0.said ?? "") })
            : []
        let taken = Set(state.accepted.map(\.id))
        let suggestions = made.filter { suggestion in
            guard !taken.contains(suggestion.id) else { return false }
            return (state.hidden[suggestion.id] ?? .distantPast) <= now
        }
        return LearningSnapshot(
            suggestions: suggestions, deadEnds: config.learns ? Learner.deadEnds(history: historyEntries) : [],
            accepted: state.accepted)
    }

    /// The failed commands a model should look at now, or none when review is off or was done lately.
    public func reviewInput(config: Config, now: Date = Date()) -> [String] {
        guard config.learns, config.reviewsFailures else { return [] }
        let state = store.load()
        if let last = state.lastReviewAt, now.timeIntervalSince(last) < Self.reviewEvery { return [] }
        let known = Set(config.aliases.keys.map(Learner.normalize))
        var phrases = Learner.deadEnds(history: history.all()).map(\.phrase)
        phrases += (reports?.all() ?? []).map { Learner.normalize($0.heard) }
        var seen = Set<String>()
        return phrases.filter { !$0.isEmpty && !known.contains($0) && seen.insert($0).inserted }
            .prefix(Self.mostToReview).map { $0 }
    }

    /// Keeps what a review found (already shown to work) and notes when it happened.
    public func saveReview(_ proven: [Suggestion], now: Date = Date()) {
        store.change { state in
            state.reviewed = proven
            state.lastReviewAt = now
        }
    }

    /// Adds what the suggestion describes to `config`, and remembers how to take it back.
    public func accept(_ suggestion: Suggestion, into config: inout Config, now: Date = Date()) {
        var record = LearningState.Accepted(id: suggestion.id, kind: suggestion.kind, title: suggestion.title, at: now)
        switch suggestion.kind {
        case .name:
            guard let said = suggestion.said, let meant = suggestion.meant else { return }
            config.aliases[said] = meant
            record.aliasKey = said
            record.aliasValue = meant
        case .page:
            guard let name = suggestion.pageName, let address = suggestion.address else { return }
            if config.links[name] == nil {
                config.links[name] = address
                record.links[name] = address
            }
        case .routine:
            guard let name = suggestion.routineName, let steps = suggestion.steps else { return }
            for (page, address) in suggestion.pages ?? [:] where config.links[page] == nil {
                config.links[page] = address
                record.links[page] = address
            }
            // Only commands that open things: a learned routine can never close, quit or run a shell command.
            config.routines.append(Routine(name: name, steps: steps.filter { $0.hasPrefix("open ") }.map { Step(say: $0) }))
            record.routineName = name
        }
        store.change { $0.accepted.removeAll { $0.id == record.id }; $0.accepted.append(record) }
    }

    /// Takes back exactly what accepting added. Anything the user changed since is left alone.
    public func remove(_ id: String, from config: inout Config) {
        let state = store.load()
        guard let record = state.accepted.first(where: { $0.id == id }) else { return }
        if let key = record.aliasKey, config.aliases[key] == record.aliasValue { config.aliases[key] = nil }
        for (name, address) in record.links where config.links[name] == address { config.links[name] = nil }
        if let routine = record.routineName { config.routines.removeAll { $0.name == routine } }
        store.change { $0.accepted.removeAll { $0.id == id } }
    }

    /// "Not now" waits 14 days; "Never" is for good.
    public func dismiss(_ suggestion: Suggestion, forever: Bool, now: Date = Date()) {
        let until = forever ? Date.distantFuture : now.addingTimeInterval(Self.notNowFor)
        store.change { $0.hidden[suggestion.id] = until }
    }

    /// Forgets what was noticed. Names, pages and routines already accepted stay in the settings.
    public func deleteAll() {
        activity.deleteAll()
        store.change { state in
            state.hidden = [:]
            state.accepted = []
        }
    }

    /// What "Find my projects" would add: projects in the usual places and in Desktop and Documents that
    /// are not already listed. Nothing is changed until the caller applies it.
    public func findMoreProjects(
        config: Config, home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> (folders: [String], projects: [String]) {
        let found = ProjectFinder.find(in: home, alsoLookIn: ProjectFinder.askFirstFolders)
        return (
            found.folders.filter { !config.searchFolders.contains($0) },
            found.projects.filter { !config.repos.contains($0) })
    }

    /// First run only: fills in folders and projects if there are none. Returns whether it changed anything.
    @discardableResult
    public func setUpIfNeeded(
        _ config: inout Config, home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        guard config.learns, !store.load().setupDone else { return false }
        store.change { $0.setupDone = true }
        guard config.searchFolders.isEmpty, config.repos.isEmpty else { return false }
        let found = ProjectFinder.find(in: home)
        guard !found.folders.isEmpty || !found.projects.isEmpty else { return false }
        config.searchFolders = found.folders
        config.repos = found.projects
        return true
    }
}
