import Foundation
import Testing

import HarkCore
@testable import HarkMac

/// A stand-in for the `claude` program: reads one JSON message per line and answers with a result line, and
/// mentions its own process number so a test can tell whether the same process answered.
private func fakeTool() throws -> (tool: ModelCLI, folder: URL) {
    let folder = FileManager.default.temporaryDirectory.appending(path: "hark-session-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let script = folder.appending(path: "fake-claude")
    try """
    #!/usr/bin/env python3
    import sys, json, os, time
    for line in sys.stdin:
        content = json.loads(line)["message"]["content"]
        print(json.dumps({"type": "system", "note": "noise"}), flush=True)
        if content == "EXIT":
            sys.exit(0)
        if content == "SLOW":
            time.sleep(30)
        if content == "FAIL":
            print(json.dumps({"type": "result", "is_error": True, "result": "something broke"}), flush=True)
            continue
        print(json.dumps({"type": "result", "is_error": False, "result": f"{os.getpid()}|{content}"}), flush=True)
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return (ModelCLI(name: "claude", label: "Fake", path: script.path), folder)
}

private func parts(_ answer: String) -> (pid: String, text: String) {
    let pieces = answer.split(separator: "|", maxSplits: 1).map(String.init)
    return (pieces[0], pieces.count > 1 ? pieces[1] : "")
}

@Suite struct CLISessionTests {
    @Test func oneProcessAnswersSeveralRequests() async throws {
        let (tool, folder) = try fakeTool()
        let session = CLISession(tool: tool, model: "haiku", folder: folder)
        let first = parts(try await session.ask("one", timeout: 10))
        let second = parts(try await session.ask("two", timeout: 10))
        #expect(first.text == "one")
        #expect(second.text == "two")
        #expect(first.pid == second.pid)
    }

    @Test func aWornProcessIsReplacedByAFreshOne() async throws {
        let (tool, folder) = try fakeTool()
        let session = CLISession(tool: tool, model: "haiku", folder: folder)
        let first = parts(try await session.ask("1", timeout: 10)).pid
        for index in 2...8 { _ = try await session.ask("\(index)", timeout: 10) }
        // The eighth request retired the process; the ninth is answered by another.
        let ninth = parts(try await session.ask("9", timeout: 10)).pid
        #expect(ninth != first)
    }

    @Test func aSlowAnswerIsStoppedAndTheNextRequestStillWorks() async throws {
        let (tool, folder) = try fakeTool()
        let session = CLISession(tool: tool, model: "haiku", folder: folder)
        let before = parts(try await session.ask("hello", timeout: 10)).pid
        let started = ContinuousClock.now
        await #expect(throws: (any Error).self) { _ = try await session.ask("SLOW", timeout: 1) }
        #expect(ContinuousClock.now - started < .seconds(5))
        let after = parts(try await session.ask("again", timeout: 10))
        #expect(after.text == "again")
        #expect(after.pid != before)
    }

    @Test func aReportedProblemIsAnErrorAndTheSessionRecovers() async throws {
        let (tool, folder) = try fakeTool()
        let session = CLISession(tool: tool, model: "haiku", folder: folder)
        do {
            _ = try await session.ask("FAIL", timeout: 10)
            Issue.record("should have thrown")
        } catch {
            #expect(error.localizedDescription.contains("something broke"))
        }
        #expect(parts(try await session.ask("fine", timeout: 10)).text == "fine")
    }

    @Test func aProcessThatExitsIsReplaced() async throws {
        let (tool, folder) = try fakeTool()
        let session = CLISession(tool: tool, model: "haiku", folder: folder)
        await #expect(throws: (any Error).self) { _ = try await session.ask("EXIT", timeout: 10) }
        #expect(parts(try await session.ask("back", timeout: 10)).text == "back")
    }

    @Test func aCancelledRequestNeverAnswersTheNextOne() async throws {
        let (tool, folder) = try fakeTool()
        let session = CLISession(tool: tool, model: "haiku", folder: folder)
        let slow = Task { try await session.ask("SLOW", timeout: 20) }
        try await Task.sleep(for: .milliseconds(300))
        slow.cancel()
        _ = try? await slow.value
        let next = parts(try await session.ask("fresh", timeout: 10))
        #expect(next.text == "fresh")
    }

    @Test func requestsAtTheSameTimeAreAnsweredInTurnAndEachGetsItsOwnAnswer() async throws {
        let (tool, folder) = try fakeTool()
        let session = CLISession(tool: tool, model: "haiku", folder: folder)
        async let a = session.ask("alpha", timeout: 10)
        async let b = session.ask("beta", timeout: 10)
        async let c = session.ask("gamma", timeout: 10)
        let answers = try await [parts(a).text, parts(b).text, parts(c).text]
        #expect(answers == ["alpha", "beta", "gamma"])
    }

    @Test func lineParsingKeepsOnlyTheResult() {
        #expect(CLISession.answer(inLine: Data(#"{"type":"assistant","message":"hi"}"#.utf8)) == nil)
        #expect(CLISession.answer(inLine: Data("not json".utf8)) == nil)
        if case .success(let text)? = CLISession.answer(inLine: Data(#"{"type":"result","result":"ok"}"#.utf8)) {
            #expect(text == "ok")
        } else {
            Issue.record("expected a result")
        }
    }
}

@Suite struct ModelWarmUpTests {
    private func config() -> Config {
        var config = Config(model: "online-model", modelURL: "https://models.example.com/v1", modelKey: "key")
        config.fallbackModel = ""
        return config
    }

    @Test func theToolIsNotStartedWhileAModelBeforeItIsHealthy() async throws {
        let (tool, folder) = try fakeTool()
        let health = ModelHealth()
        ModelWarmUp.start(for: config(), health: health, tools: [tool])
        try await Task.sleep(for: .milliseconds(400))
        let session = CLISession.shared(for: tool, model: "haiku", folder: CLIChatModel.folder)
        #expect(await !session.isRunning)
        _ = folder
    }

    @Test func theToolIsStartedOnceTheModelBeforeItIsResting() async throws {
        let (tool, _) = try fakeTool()
        let health = ModelHealth()
        let config = config()
        let online = try #require(ModelSetup.entries(for: config, tools: [tool]).first)
        health.markDown(online.choice.id, reason: "quota used up", for: 600)
        ModelWarmUp.start(for: config, health: health, tools: [tool])
        let session = CLISession.shared(for: tool, model: "haiku", folder: CLIChatModel.folder)
        try await Task.sleep(for: .milliseconds(600))
        #expect(await session.isRunning)
    }
}
