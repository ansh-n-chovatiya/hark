import Foundation

public struct AgentTurn: Sendable, Equatable {
    public let modelMs: Double
    public let tools: [String]
}

/// Lets a model call tools until the task is done, pausing for a yes before anything destructive.
public actor Agent {
    private let model: any ChatModel
    private let tools: [String: any Tool]
    private let specs: [ToolSpec]
    private let instructions: String
    private let maxTurns: Int
    private let dryRun: Bool
    private let opensThings: Set<String>
    private var carriedOn = false

    private var messages: [ChatMessage] = []
    private var pending: [ToolCall] = []
    private var summaries: [String] = []
    private var undo: [UndoStep] = []
    private var lastError: String?

    /// Of the last run, for logging.
    public private(set) var turns: [AgentTurn] = []

    /// Everything said in the last run, for working out why a command went wrong.
    public var conversation: [ChatMessage] { messages }

    public init(
        model: any ChatModel, tools: [any Tool], instructions: String, maxTurns: Int = 4,
        dryRun: Bool = false, opensThings: Set<String> = []
    ) {
        self.model = model
        self.tools = Dictionary(tools.map { ($0.spec.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.specs = tools.map(\.spec)
        self.instructions = instructions
        self.maxTurns = maxTurns
        self.dryRun = dryRun
        // After a reply that only opened something the model is asked again, because the next
        // part of the command may need what is now on screen. After any other action the run
        // ends: asked again then, a model tends to repeat the action it just took.
        self.opensThings = opensThings
    }

    public func run(heard: String, context: String) async -> AgentOutcome {
        carriedOn = false
        messages = [.system(instructions), .user(context + "\n\nHeard: \"\(heard)\"")]
        pending = []
        summaries = []
        undo = []
        lastError = nil
        turns = []
        return await askUntilSettled()
    }

    public func answer(yes: Bool) async -> AgentOutcome {
        guard !pending.isEmpty else { return .nothing("Nothing is waiting for an answer") }
        let calls = pending
        pending = []
        guard yes else { return .nothing("Cancelled") }
        if await perform(calls) { return done }
        return await askUntilSettled()
    }

    private var done: AgentOutcome {
        .done(summary: summaries.joined(separator: "; "), undo: undo)
    }

    private func askUntilSettled() async -> AgentOutcome {
        while turns.count < maxTurns {
            let reply: ChatReply
            let started = ContinuousClock.now
            do {
                reply = try await model.reply(to: messages, tools: specs)
            } catch {
                turns.append(AgentTurn(modelMs: milliseconds(since: started), tools: []))
                return summaries.isEmpty ? .failed(error.localizedDescription) : done
            }
            turns.append(AgentTurn(modelMs: milliseconds(since: started), tools: reply.calls.map(\.name)))
            messages.append(.assistant(text: reply.text, calls: reply.calls))

            if reply.calls.isEmpty { return settled(saying: reply.text) }
            if reply.calls.contains(where: { kind(of: $0) == .destructive }) {
                pending = reply.calls
                return .confirm(question: question(for: reply.calls))
            }
            // Carrying on after opening is allowed once: a model asked a second time with nothing
            // new on screen opens the same things again. In a dry run nothing was opened at all.
            let carriesOn = !dryRun && !carriedOn && reply.calls.allSatisfy { opensThings.contains($0.name) }
            if await perform(reply.calls), !carriesOn { return done }
            carriedOn = carriedOn || carriesOn
        }
        return summaries.isEmpty ? .failed(lastError ?? "Could not finish in \(maxTurns) steps") : done
    }

    private func settled(saying text: String?) -> AgentOutcome {
        guard summaries.isEmpty else { return done }
        let reason = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .nothing(reason.isEmpty ? "Nothing to do" : reason)
    }

    private func kind(of call: ToolCall) -> ToolKind? {
        tools[call.name]?.kind(for: call.arguments)
    }

    private func question(for calls: [ToolCall]) -> String {
        calls.compactMap { tools[$0.name]?.describe($0.arguments) }.joined(separator: "; ") + "?"
    }

    /// Runs the calls in order. True when the run can end without asking the model again:
    /// nothing was looked up and nothing went wrong, so the model has nothing new to read.
    private func perform(_ calls: [ToolCall]) async -> Bool {
        var modelMustSeeResults = false
        for call in calls {
            guard let tool = tools[call.name] else {
                report(error: "no tool named \(call.name)", for: call)
                modelMustSeeResults = true
                continue
            }
            let isLookup = tool.kind(for: call.arguments) == .lookup
            if dryRun && !isLookup {
                let summary = "Would: " + tool.describe(call.arguments)
                summaries.append(summary)
                send(summary, for: call)
                continue
            }
            do {
                let result = try await tool.call(call.arguments)
                send(result.output, for: call)
                if isLookup {
                    modelMustSeeResults = true
                } else {
                    summaries.append(result.summary ?? tool.describe(call.arguments))
                    if let step = result.undo { undo.append(step) }
                }
            } catch {
                report(error: error.localizedDescription, for: call)
                modelMustSeeResults = true
            }
        }
        return !modelMustSeeResults
    }

    private func report(error: String, for call: ToolCall) {
        lastError = error
        send("error: " + error, for: call)
    }

    private func send(_ output: String, for call: ToolCall) {
        messages.append(.tool(callID: call.id, name: call.name, output: output))
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1e15
    }
}
