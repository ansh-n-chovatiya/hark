import Testing

@testable import HarkCore

@Suite struct MetaTests {
    @Test func theLastCommandCanBeAskedAbout() {
        #expect(MetaCommand.parse("Why did you do that?") == .why)
        #expect(MetaCommand.parse("what did you hear") == .whatHeard)
        #expect(MetaCommand.parse("That was wrong.") == .wrong)
        #expect(MetaCommand.parse("what can I say") == .help)
    }

    @Test func rememberTakesTheName() {
        #expect(MetaCommand.parse("Remember that as Kubernetes") == .remember("kubernetes"))
        #expect(MetaCommand.parse("no I meant the budget report") == .remember("the budget report"))
        #expect(MetaCommand.parse("remember that as") == nil)
    }

    @Test func ordinaryCommandsAreNotMeta() {
        #expect(MetaCommand.parse("open slack") == nil)
        #expect(MetaCommand.parse("why not switch to chrome and then close the other tab please now") == nil)
    }

    @Test func theExplanationSaysWhoDecided() {
        var timings = Timings(at: .now, raw: "open slack", verb: "open", outcome: "done", transcribeMs: 0, parseMs: 0,
                              matchMs: 0, actMs: 0, totalMs: 800, summary: "Switched to Slack")
        #expect(timings.explanation.contains("rules for finding what is open"))
        #expect(timings.explanation.contains("0.8 s"))
        timings.model = "Claude Code (Haiku)"
        #expect(timings.decidedBy.contains("Claude Code"))
    }

    @Test func aFailureSaysWhatToDoNext() {
        #expect(Recovery.hint(for: "Hark is not allowed to control Brave Browser.") != nil)
        #expect(Recovery.hint(for: "Brave did not answer") != nil)
        #expect(Recovery.hint(for: "something odd") == nil)
    }
}
