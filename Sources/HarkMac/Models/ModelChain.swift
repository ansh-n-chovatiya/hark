import Foundation
import HarkCore
import Network
import os

/// One model Hark can ask, in the order it is tried.
public struct ModelChoice: Sendable {
    public let id: String
    public let label: String
    public let model: any ChatModel
    /// A small model standing in for a better one. Hark does not let it plan anything that closes or quits.
    public let isStandIn: Bool
    /// Needs the internet to answer. Skipped at once when the Mac is offline, instead of waiting for it to fail.
    public var needsNetwork = false
}

/// Whether the Mac can reach the internet at all, watched by the system. Assumed yes until it says otherwise.
public final class NetworkStatus: Sendable {
    public static let shared = NetworkStatus()

    private let online = OSAllocatedUnfairLock(initialState: true)
    private let monitor = NWPathMonitor()

    public var isOnline: Bool { online.withLock { $0 } }

    public func start() {
        monitor.pathUpdateHandler = { [online] path in online.withLock { $0 = path.status == .satisfied } }
        monitor.start(queue: DispatchQueue(label: "hark.network"))
    }
}

/// Which models just failed, why, and until when. A model that is out of quota is not asked again
/// for a while, so a command does not wait for it every time. Shared by everything that asks a model.
public final class ModelHealth: Sendable {
    public static let shared = ModelHealth()

    public struct Down: Sendable, Equatable {
        public var until: Date
        public var reason: String
    }

    private let down = OSAllocatedUnfairLock<[String: Down]>(initialState: [:])

    public func status(of id: String, now: Date = Date()) -> Down? {
        down.withLock { down in
            guard let entry = down[id] else { return nil }
            if entry.until <= now {
                down[id] = nil
                return nil
            }
            return entry
        }
    }

    public func markDown(_ id: String, reason: String, for seconds: TimeInterval, now: Date = Date()) {
        down.withLock { $0[id] = Down(until: now.addingTimeInterval(seconds), reason: reason) }
    }

    public func markUp(_ id: String) {
        down.withLock { $0[id] = nil }
    }

    /// How long to leave a model alone after this failure, and what to call it.
    public static func cooldown(for message: String) -> (seconds: TimeInterval, reason: String) {
        let text = message.lowercased()
        if text.contains("quota") || text.contains("429") { return (10 * 60, "quota used up") }
        if text.contains("401") || text.contains("403") || text.contains("did not accept this key") || text.contains("unauthor") {
            return (30 * 60, "key not accepted")
        }
        if text.contains("could not be started") || text.contains("not found") { return (30 * 60, "not available") }
        if text.contains("in time") { return (60, "too slow") }
        if text.contains("could not be reached") || text.contains("connection") { return (2 * 60, "not reachable") }
        if text.contains("terminated") || text.contains("error 5") { return (5 * 60, "not working") }
        return (2 * 60, "failed")
    }
}

struct ModelChainError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Tries models in order and uses the first that answers. A model that is known to be down is not
/// called at all; one that fails hands over to the next at once; one that is only slow gets a head
/// start before the next is asked alongside it. If every model is marked down they are all tried
/// anyway, in order, because one may have come back.
public struct ModelChain: ChatModel {
    private final class Last: Sendable {
        private let value = OSAllocatedUnfairLock<(label: String, standIn: Bool)>(initialState: ("", false))
        func set(_ choice: ModelChoice) { value.withLock { $0 = (choice.label, choice.isStandIn) } }
        func clear() { value.withLock { $0 = ("", false) } }
        var current: (label: String, standIn: Bool) { value.withLock { $0 } }
    }

    public let choices: [ModelChoice]
    private let headStart: Duration
    private let last = Last()
    private let health: ModelHealth
    private let isOnline: @Sendable () -> Bool

    public init(
        choices: [ModelChoice], headStart: Duration = .milliseconds(3500), health: ModelHealth = .shared,
        isOnline: @escaping @Sendable () -> Bool = { NetworkStatus.shared.isOnline }
    ) {
        self.choices = choices
        self.headStart = headStart
        self.health = health
        self.isOnline = isOnline
    }

    public var isEmpty: Bool { choices.isEmpty }
    /// Whether the model that answered last was a small stand-in.
    public var lastWasStandIn: Bool { last.current.standIn }
    public var lastLabel: String { last.current.label }

    private enum Event: Sendable {
        case answered(Int, ChatReply)
        case failed(Int, String)
        case slow(Int)
    }

    public func reply(to messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        // Offline, a model that needs the internet is not even tried; one on this Mac answers at once.
        let reachable = isOnline() ? choices : choices.filter { !$0.needsNetwork }
        let live = reachable.filter { self.health.status(of: $0.id) == nil }
        let order = live.isEmpty ? (reachable.isEmpty ? choices : reachable) : live
        guard !order.isEmpty else { throw ModelChainError(message: "No model is set up.") }
        // Until one answers, nothing is credited, so a failed command never shows the last answerer.
        last.clear()
        let (headStart, health, last) = (self.headStart, self.health, self.last)

        return try await withThrowingTaskGroup(of: Event.self) { group in
            var next = 0
            var running = 0
            var finished = Set<Int>()
            var failures: [String] = []

            func start() {
                guard next < order.count else { return }
                let index = next
                next += 1
                running += 1
                let choice = order[index]
                group.addTask {
                    do {
                        return .answered(index, try await choice.model.reply(to: messages, tools: tools))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return .failed(index, error.localizedDescription)
                    }
                }
                group.addTask {
                    try await Task.sleep(for: headStart)
                    return .slow(index)
                }
            }

            start()
            while let event = try await group.next() {
                switch event {
                case .answered(let index, let reply):
                    group.cancelAll()
                    health.markUp(order[index].id)
                    last.set(order[index])
                    return reply
                case .failed(let index, let message):
                    // A model that stopped only because the request was cancelled (it timed out, or another
                    // answered) did not fail, so it is not marked as resting.
                    guard !Task.isCancelled else { throw CancellationError() }
                    finished.insert(index)
                    running -= 1
                    let (seconds, reason) = ModelHealth.cooldown(for: message)
                    health.markDown(order[index].id, reason: reason, for: seconds)
                    failures.append("\(order[index].label): \(message)")
                    if next < order.count {
                        start()
                    } else if running == 0 {
                        throw ModelChainError(message: failures.joined(separator: " Then: "))
                    }
                case .slow(let index):
                    // Only the newest model still waiting is given company.
                    if !finished.contains(index), index == next - 1 { start() }
                }
            }
            throw ModelChainError(message: failures.isEmpty ? "The model gave no reply." : failures.joined(separator: " Then: "))
        }
    }
}

/// Builds the chain for these settings: the online model, then AI tools already on the Mac, then the
/// model on this Mac, unless the user has reordered or turned some off.
public enum ModelSetup {
    public struct Entry: Sendable {
        public let key: String
        public let choice: ModelChoice
        public let isOn: Bool
    }

    public struct Result {
        public let chain: ModelChain?
        /// The model that runs on this Mac, which is warmed up between commands.
        public let local: OpenAIChatModel?
    }

    /// Every model that could be used, in the order they would be tried, with whether each is turned on.
    public static func entries(for config: Config, tools: [ModelCLI] = ModelCLIs.found) -> [Entry] {
        var found: [(key: String, choice: ModelChoice)] = []
        var seen = Set<String>()
        func add(_ key: String, _ id: String, _ label: String, _ model: any ChatModel, standIn: Bool) {
            guard seen.insert(id).inserted else { return }
            let isLocal = (model as? OpenAIChatModel)?.isLocal == true
            found.append((key, ModelChoice(id: id, label: label, model: model, isStandIn: standIn, needsNetwork: !isLocal)))
        }
        if let main = OpenAIChatModel(url: config.modelURL, models: config.model, key: config.modelKey) {
            add("online", "openai:\(config.modelURL)#\(config.model)", main.isLocal ? "Model on this Mac" : "Online model", main, standIn: false)
        }
        if config.cli != "off" {
            for tool in tools {
                add("cli:\(tool.name)", "cli:\(tool.name)", "\(tool.label) (\(config.cliModel.capitalized))",
                    CLIChatModel(tool, model: config.cliModel), standIn: false)
            }
        }
        if !config.fallbackModel.isEmpty,
           let fallback = OpenAIChatModel(url: config.fallbackModelURL, models: config.fallbackModel, key: "") {
            add("local", "openai:\(config.fallbackModelURL)#\(config.fallbackModel)", "Model on this Mac", fallback, standIn: true)
        }
        // The user's order first, then anything they have not placed, in the usual order.
        let wanted = config.modelOrder
        let ordered = found.enumerated().sorted { first, second in
            let (a, b) = (wanted.firstIndex(of: first.element.key) ?? Int.max, wanted.firstIndex(of: second.element.key) ?? Int.max)
            return a == b ? first.offset < second.offset : a < b
        }.map(\.element)
        return ordered.map { Entry(key: $0.key, choice: $0.choice, isOn: !config.modelsOff.contains($0.key)) }
    }

    public static func make(
        for config: Config, headStart: Duration = .milliseconds(3500), tools: [ModelCLI] = ModelCLIs.found
    ) -> Result {
        guard config.useModel else { return Result(chain: nil, local: nil) }
        let on = entries(for: config, tools: tools).filter(\.isOn)
        let local = on.compactMap { $0.choice.model as? OpenAIChatModel }.first { $0.isLocal }
        return Result(chain: on.isEmpty ? nil : ModelChain(choices: on.map(\.choice), headStart: headStart), local: local)
    }
}

/// Starts what takes a moment to start, while the user is still speaking. Only an AI tool that is likely to be
/// asked is started: when a model before it is healthy it will answer, so the tool is left alone until that
/// model fails (which marks it as resting, and the next key press then starts the tool).
public enum ModelWarmUp {
    public static func start(for config: Config, health: ModelHealth = .shared, tools: [ModelCLI] = ModelCLIs.found) {
        for entry in ModelSetup.entries(for: config, tools: tools) where entry.isOn {
            if let tool = entry.choice.model as? CLIChatModel {
                tool.warmUp()
                return
            }
            if health.status(of: entry.choice.id) == nil { return }
        }
    }
}
