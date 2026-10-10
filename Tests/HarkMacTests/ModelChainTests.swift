import Foundation
import Testing

import HarkCore
@testable import HarkMac

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func hit() { lock.withLock { count += 1 } }
}

private struct FakeModel: ChatModel {
    enum Behaviour { case answers(String), fails(String), slow(String, Duration) }
    let behaviour: Behaviour
    let calls = Counter()

    func reply(to messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        calls.hit()
        switch behaviour {
        case .answers(let text): return ChatReply(text: text, calls: [])
        case .fails(let message): throw ModelChainError(message: message)
        case .slow(let text, let delay):
            try await Task.sleep(for: delay)
            return ChatReply(text: text, calls: [])
        }
    }
}

@Suite struct ModelChainTests {
    @Test func offlineTheInternetModelsAreSkippedAndTheOneOnThisMacAnswers() async throws {
        let online = FakeModel(behaviour: .answers("online"))
        let local = FakeModel(behaviour: .answers("local"))
        let choices = [
            ModelChoice(id: "o-\(UUID())", label: "Online", model: online, isStandIn: false, needsNetwork: true),
            ModelChoice(id: "l-\(UUID())", label: "Local", model: local, isStandIn: true, needsNetwork: false),
        ]
        let chain = ModelChain(choices: choices, headStart: .seconds(5), health: ModelHealth(), isOnline: { false })
        #expect(try await chain.reply(to: [], tools: []).text == "local")
        #expect(online.calls.value == 0)
    }

    @Test func offlineWithOnlyInternetModelsStillTriesThem() async throws {
        let online = FakeModel(behaviour: .answers("online"))
        let choices = [ModelChoice(id: "o-\(UUID())", label: "Online", model: online, isStandIn: false, needsNetwork: true)]
        let chain = ModelChain(choices: choices, headStart: .seconds(5), health: ModelHealth(), isOnline: { false })
        #expect(try await chain.reply(to: [], tools: []).text == "online")
    }

    private func chain(_ models: [(String, FakeModel, Bool)], headStart: Duration = .seconds(5)) -> ModelChain {
        let choices = models.map { ModelChoice(id: "t-\(UUID().uuidString)-\($0.0)", label: $0.0, model: $0.1, isStandIn: $0.2) }
        return ModelChain(choices: choices, headStart: headStart, health: ModelHealth())
    }

    @Test func aFailedModelHandsOverToTheNextAtOnce() async throws {
        let first = FakeModel(behaviour: .fails("The online model's quota is used up (error 429)."))
        let second = FakeModel(behaviour: .answers("from the tool"))
        let chain = chain([("Online", first, false), ("Tool", second, false)])
        let reply = try await chain.reply(to: [], tools: [])
        #expect(reply.text == "from the tool")
        #expect(first.calls.value == 1)
        #expect(chain.lastLabel == "Tool")
    }

    @Test func aModelThatIsOutOfQuotaIsNotCalledAgain() async throws {
        let first = FakeModel(behaviour: .fails("quota is used up (error 429)"))
        let second = FakeModel(behaviour: .answers("ok"))
        let chain = chain([("Online", first, false), ("Tool", second, false)])
        _ = try await chain.reply(to: [], tools: [])
        _ = try await chain.reply(to: [], tools: [])
        _ = try await chain.reply(to: [], tools: [])
        #expect(first.calls.value == 1)
        #expect(second.calls.value == 3)
    }

    @Test func eachFailureFallsThroughToTheNextWorkingOne() async throws {
        let one = FakeModel(behaviour: .fails("error 429"))
        let two = FakeModel(behaviour: .fails("The model could not be reached"))
        let three = FakeModel(behaviour: .fails("The tool stopped"))
        let four = FakeModel(behaviour: .answers("fourth"))
        let chain = chain([("1", one, false), ("2", two, false), ("3", three, false), ("4", four, true)])
        #expect(try await chain.reply(to: [], tools: []).text == "fourth")
        #expect(chain.lastWasStandIn)
    }

    @Test func whenEveryModelIsMarkedDownTheyAreAllTriedAnyway() async throws {
        let health = ModelHealth()
        let model = FakeModel(behaviour: .answers("back"))
        let choice = ModelChoice(id: "only", label: "Only", model: model, isStandIn: false)
        health.markDown("only", reason: "quota used up", for: 600)
        let chain = ModelChain(choices: [choice], headStart: .seconds(5), health: health)
        #expect(try await chain.reply(to: [], tools: []).text == "back")
        #expect(health.status(of: "only") == nil)
    }

    @Test func aSlowModelGetsAHeadStartThenTheNextOneRacesIt() async throws {
        let slow = FakeModel(behaviour: .slow("slow", .seconds(5)))
        let quick = FakeModel(behaviour: .answers("quick"))
        let chain = chain([("Slow", slow, false), ("Quick", quick, false)], headStart: .milliseconds(100))
        let started = ContinuousClock.now
        #expect(try await chain.reply(to: [], tools: []).text == "quick")
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test func aFastPrimaryNeverStartsTheOthers() async throws {
        let first = FakeModel(behaviour: .answers("first"))
        let second = FakeModel(behaviour: .answers("second"))
        let chain = chain([("1", first, false), ("2", second, false)], headStart: .seconds(3))
        #expect(try await chain.reply(to: [], tools: []).text == "first")
        #expect(second.calls.value == 0)
    }

    @Test func whenNothingWorksTheErrorSaysWhatEachOneSaid() async {
        let chain = chain([("A", FakeModel(behaviour: .fails("one broke")), false), ("B", FakeModel(behaviour: .fails("two broke")), false)])
        do {
            _ = try await chain.reply(to: [], tools: [])
            Issue.record("should have thrown")
        } catch {
            #expect(error.localizedDescription.contains("one broke"))
            #expect(error.localizedDescription.contains("two broke"))
        }
    }

    @Test func failuresAreSortedIntoHowLongToWait() {
        #expect(ModelHealth.cooldown(for: "You exceeded your current quota").reason == "quota used up")
        #expect(ModelHealth.cooldown(for: "error 429").seconds == 600)
        #expect(ModelHealth.cooldown(for: "The service did not accept this key").reason == "key not accepted")
        #expect(ModelHealth.cooldown(for: "llama-server process has terminated").reason == "not working")
        #expect(ModelHealth.cooldown(for: "The model did not answer in time").seconds == 60)
    }

    @Test func coolDownsEndOnTime() {
        let health = ModelHealth()
        let now = Date()
        health.markDown("a", reason: "quota used up", for: 600, now: now)
        #expect(health.status(of: "a", now: now.addingTimeInterval(599)) != nil)
        #expect(health.status(of: "a", now: now.addingTimeInterval(601)) == nil)
    }

    @Test func setupPutsTheOnlineModelFirstAndTheLocalOneLast() {
        var config = Config(model: "online-model", modelURL: "https://models.example.com/v1", modelKey: "key")
        config.fallbackModel = "small"
        config.fallbackModelURL = "http://127.0.0.1:11434/v1"
        config.cli = "off"
        let labels = ModelSetup.make(for: config, tools: []).chain?.choices.map(\.label)
        #expect(labels == ["Online model", "Model on this Mac"])
        config.useModel = false
        #expect(ModelSetup.make(for: config, tools: []).chain == nil)
    }

    @Test func theUsersOrderAndOffSwitchesAreHonoured() {
        var config = Config(model: "online-model", modelURL: "https://models.example.com/v1", modelKey: "key")
        config.fallbackModel = "small"
        config.fallbackModelURL = "http://127.0.0.1:11434/v1"
        #expect(ModelSetup.entries(for: config, tools: []).map(\.key) == ["online", "local"])
        config.modelOrder = ["local", "online"]
        #expect(ModelSetup.entries(for: config, tools: []).map(\.key) == ["local", "online"])
        #expect(ModelSetup.make(for: config, tools: []).chain?.choices.map(\.label) == ["Model on this Mac", "Online model"])
        config.modelsOff = ["online"]
        #expect(ModelSetup.entries(for: config, tools: []).map(\.isOn) == [true, false])
        #expect(ModelSetup.make(for: config, tools: []).chain?.choices.map(\.label) == ["Model on this Mac"])
        config.modelsOff = ["online", "local"]
        #expect(ModelSetup.make(for: config, tools: []).chain == nil)
    }

    @Test func aModelNotPlacedYetGoesLastInTheUsualOrder() {
        var config = Config(model: "online-model", modelURL: "https://models.example.com/v1", modelKey: "key")
        config.fallbackModel = "small"
        config.fallbackModelURL = "http://127.0.0.1:11434/v1"
        config.modelOrder = ["local"]
        #expect(ModelSetup.entries(for: config, tools: []).map(\.key) == ["local", "online"])
    }

    @Test func theOrderAndSwitchesSurviveSaving() throws {
        var config = Config()
        config.modelOrder = ["local", "online"]
        config.modelsOff = ["cli:claude"]
        let data = try JSONEncoder().encode(config)
        let loaded = try JSONDecoder().decode(Config.self, from: data)
        #expect(loaded.modelOrder == ["local", "online"])
        #expect(loaded.modelsOff == ["cli:claude"])
        #expect(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).modelOrder.isEmpty)
    }

    @Test func theToolsModelIsHaikuByDefaultAndSurvivesSaving() throws {
        #expect(Config().cliModel == "haiku")
        var config = Config()
        config.cliModel = "sonnet"
        let loaded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(loaded.cliModel == "sonnet")
        #expect(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).cliModel == "haiku")
    }

    @Test func theOrderShowsWhichToolModelIsUsed() {
        let tools = [ModelCLI(name: "claude", label: "Claude Code", path: "/usr/local/bin/claude")]
        var config = Config(model: "online-model", modelURL: "https://models.example.com/v1", modelKey: "key")
        config.cliModel = "sonnet"
        #expect(ModelSetup.entries(for: config, tools: tools).map(\.choice.label).contains("Claude Code (Sonnet)"))
    }
}
