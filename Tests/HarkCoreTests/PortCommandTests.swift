import Testing

@testable import HarkCore

@Suite struct PortCommandTests {
    @Test func portQuestionsAreRecognised() {
        #expect(PortCommand.parse("what's on 3000") == .whatsOn(3000))
        #expect(PortCommand.parse("What is running on port 5173?") == .whatsOn(5173))
        #expect(PortCommand.parse("what's running") == .whatsOn(nil))
        #expect(PortCommand.parse("open localhost 8080") == .open(8080))
        #expect(PortCommand.parse("tell me when 3000 is up") == .tellWhenUp(3000))
    }

    @Test func otherCommandsAreNotPortCommands() {
        #expect(PortCommand.parse("open slack") == nil)
        #expect(PortCommand.parse("what is the weather") == nil)
        #expect(PortCommand.parse("tell me when the build finishes") == nil)
    }

    @Test func hereIsFilledFromTheFrontProject() {
        let commands = Routines.commands(for: "git -C {here} status", argument: nil, repos: [], here: "/work/shop")
        #expect(commands.count == 1)
        #expect(commands[0].text == "git -C \"$HARK_HERE\" status")
        #expect(commands[0].environment["HARK_HERE"] == "/work/shop")
        #expect(commands[0].label == "shop")
        let routine = Routine(name: "status here", steps: [Step(shell: "git -C {here} status")])
        #expect(Routines.usesHere(routine))
        #expect(!Routines.usesHere(Routine(name: "x", steps: [Step(shell: "date")])))
    }
}
