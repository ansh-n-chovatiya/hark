import Foundation
import Testing
@testable import HarkCore

private struct ScriptedFailure: LocalizedError {
    let errorDescription: String?
}

private actor ScriptedModel: ChatModel {
    private var replies: [Result<ChatReply, ScriptedFailure>]
    private(set) var received: [[ChatMessage]] = []
    private(set) var offeredTools: [[String]] = []

    init(_ replies: [Result<ChatReply, ScriptedFailure>]) {
        self.replies = replies
    }

    func reply(to messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        received.append(messages)
        offeredTools.append(tools.map(\.name))
        guard !replies.isEmpty else { throw ScriptedFailure(errorDescription: "script ran out") }
        return try replies.removeFirst().get()
    }
}

private actor CallLog {
    private(set) var calls: [String] = []
    func add(_ call: String) { calls.append(call) }
}

private struct FakeTool: Tool {
    let spec: ToolSpec
    let log: CallLog
    var failure: String?
    var destructiveTarget: String?

    init(_ name: String, _ kind: ToolKind, log: CallLog, failure: String? = nil, destructiveTarget: String? = nil) {
        self.spec = ToolSpec(name: name, description: name, parameters: .object([:]), kind: kind)
        self.log = log
        self.failure = failure
        self.destructiveTarget = destructiveTarget
    }

    private func target(_ arguments: JSONValue) -> String {
        arguments["target"]?.string ?? "it"
    }

    func describe(_ arguments: JSONValue) -> String {
        "\(spec.name) \(target(arguments))"
    }

    func kind(for arguments: JSONValue) -> ToolKind {
        target(arguments) == destructiveTarget ? .destructive : spec.kind
    }

    func call(_ arguments: JSONValue) async throws -> ToolResult {
        let name = describe(arguments)
        await log.add(name)
        if let failure { throw ScriptedFailure(errorDescription: failure) }
        if spec.kind == .lookup { return ToolResult(output: "found \(target(arguments))") }
        return ToolResult(output: "ok", summary: "Did \(name)", undo: UndoStep(summary: "Undo \(name)") {})
    }
}

private func call(_ name: String, _ target: String, id: String = "c1") -> ToolCall {
    ToolCall(id: id, name: name, arguments: .object(["target": .string(target)]))
}

private func says(_ text: String?, _ calls: ToolCall...) -> Result<ChatReply, ScriptedFailure> {
    .success(ChatReply(text: text, calls: calls))
}

private func agent(
    _ model: ScriptedModel, _ tools: [FakeTool], maxTurns: Int = 4, dryRun: Bool = false
) -> Agent {
    Agent(model: model, tools: tools, instructions: "Be careful.", maxTurns: maxTurns, dryRun: dryRun)
}

private func toolOutputs(_ messages: [ChatMessage]) -> [String] {
    messages.compactMap {
        if case .tool(_, _, let output) = $0 { return output }
        return nil
    }
}

@Test func agentEndsAfterOneActionInOneModelTurn() async {
    let log = CallLog()
    let model = ScriptedModel([says(nil, call("open", "notes"))])
    let agent = agent(model, [FakeTool("open", .action, log: log)])

    let outcome = await agent.run(heard: "open notes", context: "Apps: Notes")

    guard case .done(let summary, let undo) = outcome else {
        Issue.record("expected done, got \(outcome)")
        return
    }
    #expect(summary == "Did open notes")
    #expect(undo.map(\.summary) == ["Undo open notes"])
    #expect(await log.calls == ["open notes"])
    #expect(await model.received.count == 1)
    #expect(await agent.turns.map(\.tools) == [["open"]])
    #expect(await model.offeredTools == [["open"]])
}

@Test func agentStartsWithInstructionsThenContextAndHeard() async {
    let model = ScriptedModel([says("Nothing matches.")])
    let agent = agent(model, [])

    let outcome = await agent.run(heard: "open notes", context: "Apps: Notes")

    #expect(await model.received.first == [
        .system("Be careful."), .user("Apps: Notes\n\nHeard: \"open notes\""),
    ])
    guard case .nothing(let reason) = outcome else {
        Issue.record("expected nothing, got \(outcome)")
        return
    }
    #expect(reason == "Nothing matches.")
}

@Test func agentGivesFallbackLineWhenModelSaysNothing() async {
    let agent = agent(ScriptedModel([says(nil)]), [])

    guard case .nothing(let reason) = await agent.run(heard: "hm", context: "") else {
        Issue.record("expected nothing")
        return
    }
    #expect(!reason.isEmpty)
}

@Test func agentLookupThenActionTakesTwoTurnsAndModelSeesLookupOutput() async {
    let log = CallLog()
    let model = ScriptedModel([
        says(nil, call("find", "report", id: "a")),
        says(nil, call("open", "report", id: "b")),
    ])
    let agent = agent(model, [FakeTool("find", .lookup, log: log), FakeTool("open", .action, log: log)])

    let outcome = await agent.run(heard: "open the report", context: "")

    guard case .done(let summary, _) = outcome else {
        Issue.record("expected done, got \(outcome)")
        return
    }
    #expect(summary == "Did open report")
    #expect(await log.calls == ["find report", "open report"])
    let received = await model.received
    #expect(received.count == 2)
    #expect(received[1].contains(.tool(callID: "a", name: "find", output: "found report")))
    #expect(received[1].contains(.assistant(text: nil, calls: [call("find", "report", id: "a")])))
}

@Test func agentDestructiveCallAsksFirstAndRunsOnlyAfterYes() async {
    let log = CallLog()
    let model = ScriptedModel([says(nil, call("hide", "mail", id: "a"), call("quit", "chat", id: "b"))])
    let agent = agent(model, [FakeTool("hide", .action, log: log), FakeTool("quit", .destructive, log: log)])

    let asked = await agent.run(heard: "hide mail and quit chat", context: "")

    guard case .confirm(let question) = asked else {
        Issue.record("expected confirm, got \(asked)")
        return
    }
    #expect(question == "hide mail; quit chat?")
    #expect(await log.calls.isEmpty)

    let outcome = await agent.answer(yes: true)

    guard case .done(let summary, let undo) = outcome else {
        Issue.record("expected done, got \(outcome)")
        return
    }
    #expect(summary == "Did hide mail; Did quit chat")
    #expect(undo.map(\.summary) == ["Undo hide mail", "Undo quit chat"])
    #expect(await log.calls == ["hide mail", "quit chat"])
    #expect(await model.received.count == 1)
}

@Test func agentAnsweringNoRunsNothing() async {
    let log = CallLog()
    let model = ScriptedModel([says(nil, call("quit", "chat"))])
    let agent = agent(model, [FakeTool("quit", .destructive, log: log)])

    _ = await agent.run(heard: "quit chat", context: "")
    let outcome = await agent.answer(yes: false)

    guard case .nothing(let reason) = outcome else {
        Issue.record("expected nothing, got \(outcome)")
        return
    }
    #expect(reason == "Cancelled")
    #expect(await log.calls.isEmpty)

    guard case .nothing = await agent.answer(yes: true) else {
        Issue.record("a second answer should find nothing pending")
        return
    }
    #expect(await log.calls.isEmpty)
}

@Test func agentAnswerWithNothingPendingDoesNothing() async {
    let agent = agent(ScriptedModel([]), [])

    guard case .nothing = await agent.answer(yes: true) else {
        Issue.record("expected nothing")
        return
    }
}

@Test func agentAsksWhenAnActionToolSaysThisCallIsDestructive() async {
    let log = CallLog()
    let model = ScriptedModel([says(nil, call("menu", "Close Window"))])
    let agent = agent(model, [FakeTool("menu", .action, log: log, destructiveTarget: "Close Window")])

    let asked = await agent.run(heard: "close this", context: "")

    guard case .confirm(let question) = asked else {
        Issue.record("expected confirm, got \(asked)")
        return
    }
    #expect(question == "menu Close Window?")
    #expect(await log.calls.isEmpty)
}

@Test func agentReportsUnknownAndThrowingToolsSoTheModelCanTryAgain() async {
    let log = CallLog()
    let model = ScriptedModel([
        says(nil, call("vanish", "notes", id: "a")),
        says(nil, call("broken", "notes", id: "b")),
        says(nil, call("open", "notes", id: "c")),
    ])
    let agent = agent(model, [
        FakeTool("broken", .action, log: log, failure: "no such window"),
        FakeTool("open", .action, log: log),
    ])

    let outcome = await agent.run(heard: "open notes", context: "")

    guard case .done(let summary, let undo) = outcome else {
        Issue.record("expected done, got \(outcome)")
        return
    }
    #expect(summary == "Did open notes")
    #expect(undo.count == 1)
    let received = await model.received
    #expect(received.count == 3)
    let outputs = toolOutputs(received[2])
    #expect(outputs.count == 2)
    #expect(outputs.allSatisfy { $0.hasPrefix("error: ") })
    #expect(outputs[0].contains("vanish"))
    #expect(outputs[1] == "error: no such window")
}

@Test func agentStopsAModelThatKeepsLookingThingsUp() async {
    let log = CallLog()
    let lookups = (0..<10).map { says(nil, call("find", "thing", id: "l\($0)")) }
    let model = ScriptedModel(lookups)
    let agent = agent(model, [FakeTool("find", .lookup, log: log)], maxTurns: 3)

    let outcome = await agent.run(heard: "find the thing", context: "")

    guard case .failed(let reason) = outcome else {
        Issue.record("expected failed, got \(outcome)")
        return
    }
    #expect(!reason.isEmpty)
    #expect(await model.received.count == 3)
    #expect(await agent.turns.count == 3)
    #expect(await log.calls.count == 3)
}

@Test func agentFailsWithTheLastToolErrorWhenTurnsRunOut() async {
    let log = CallLog()
    let model = ScriptedModel([says(nil, call("broken", "notes")), says(nil, call("broken", "notes"))])
    let agent = agent(model, [FakeTool("broken", .action, log: log, failure: "no such window")], maxTurns: 2)

    guard case .failed(let reason) = await agent.run(heard: "open notes", context: "") else {
        Issue.record("expected failed")
        return
    }
    #expect(reason == "no such window")
}

@Test func agentDryRunLooksUpButCallsNoAction() async {
    let log = CallLog()
    let model = ScriptedModel([
        says(nil, call("find", "notes", id: "a")),
        says(nil, call("open", "notes", id: "b")),
    ])
    let agent = agent(
        model, [FakeTool("find", .lookup, log: log), FakeTool("open", .action, log: log)], dryRun: true)

    let outcome = await agent.run(heard: "open notes", context: "")

    guard case .done(let summary, let undo) = outcome else {
        Issue.record("expected done, got \(outcome)")
        return
    }
    #expect(summary == "Would: open notes")
    #expect(undo.isEmpty)
    #expect(await log.calls == ["find notes"])
}

@Test func agentDryRunStillAsksBeforeADestructiveCallAndNeverCallsIt() async {
    let log = CallLog()
    let model = ScriptedModel([says(nil, call("quit", "chat"))])
    let agent = agent(model, [FakeTool("quit", .destructive, log: log)], dryRun: true)

    guard case .confirm = await agent.run(heard: "quit chat", context: "") else {
        Issue.record("expected confirm")
        return
    }
    guard case .done(let summary, _) = await agent.answer(yes: true) else {
        Issue.record("expected done")
        return
    }
    #expect(summary == "Would: quit chat")
    #expect(await log.calls.isEmpty)
}

@Test func agentFailsWhenTheModelThrows() async {
    let model = ScriptedModel([.failure(ScriptedFailure(errorDescription: "model unreachable"))])
    let agent = agent(model, [])

    guard case .failed(let reason) = await agent.run(heard: "open notes", context: "") else {
        Issue.record("expected failed")
        return
    }
    #expect(reason == "model unreachable")
}

@Test func agentKeepsWhatRanWhenTheModelThrowsLater() async {
    let log = CallLog()
    let model = ScriptedModel([
        says(nil, call("find", "notes", id: "a"), call("open", "notes", id: "b")),
        .failure(ScriptedFailure(errorDescription: "model unreachable")),
    ])
    let agent = agent(model, [FakeTool("find", .lookup, log: log), FakeTool("open", .action, log: log)])

    guard case .done(let summary, _) = await agent.run(heard: "open notes", context: "") else {
        Issue.record("expected done")
        return
    }
    #expect(summary == "Did open notes")
}

@Test func agentCarriesOnAfterOpeningButNotAfterOtherActions() async {
    let log = CallLog()
    let model = ScriptedModel([
        says(nil, call("open", "calculator")),
        says(nil, call("press", "seven")),
        says(nil, call("press", "seven")),
    ])
    let agent = Agent(
        model: model, tools: [FakeTool("open", .action, log: log), FakeTool("press", .action, log: log)],
        instructions: "Be careful.", opensThings: ["open"])

    let outcome = await agent.run(heard: "open the calculator and press seven", context: "")

    guard case .done(let summary, _) = outcome else {
        Issue.record("expected done, got \(outcome)")
        return
    }
    #expect(summary == "Did open calculator; Did press seven")
    #expect(await log.calls == ["open calculator", "press seven"])
    #expect(await model.received.count == 2)
}
