import Foundation

public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case app, window, tab, file, clip, workspace, routine
}

public struct Item: Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: ItemKind
    public let title: String
    public let detail: String
    public let owner: String
    public let lastUsed: Date?
    public let payload: [String: String]

    public init(
        id: String,
        kind: ItemKind,
        title: String,
        detail: String = "",
        owner: String = "",
        lastUsed: Date? = nil,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.owner = owner
        self.lastUsed = lastUsed
        self.payload = payload
    }
}

public enum Verb: String, Sendable, CaseIterable {
    case open, close, closeDuplicates, paste, save, restore, hide, run, undo, pick, quit, newTab
}

public struct Command: Sendable, Equatable {
    public let verb: Verb
    public let query: String
    public let kinds: Set<ItemKind>
    public let owner: String?
    public let raw: String

    public init(verb: Verb, query: String, kinds: Set<ItemKind> = [], owner: String? = nil, raw: String) {
        self.verb = verb
        self.query = query
        self.kinds = kinds
        self.owner = owner
        self.raw = raw
    }
}

public struct Match: Sendable {
    public let item: Item
    public let score: Double

    public init(item: Item, score: Double) {
        self.item = item
        self.score = score
    }
}

public struct UndoStep: Sendable {
    public let summary: String
    public let run: @Sendable () async throws -> Void

    public init(summary: String, run: @escaping @Sendable () async throws -> Void) {
        self.summary = summary
        self.run = run
    }
}

public protocol ItemSource: Sendable {
    var kinds: Set<ItemKind> { get }
    func refresh() async
    func items(for command: Command) async -> [Item]
    func perform(_ verb: Verb, on item: Item) async throws -> UndoStep?
}

public protocol Transcriber: Sendable {
    func prepare() async throws
    func start() async throws
    var partials: AsyncStream<String> { get }
    func finish() async throws -> String
}

public enum Outcome: Sendable {
    case done(String), choose([Match]), confirm(String), notUnderstood(String), failed(String)
    /// Something the user asked to know, which stays on screen long enough to read.
    case answer(String)
}
