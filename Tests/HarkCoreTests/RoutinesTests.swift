import Foundation
import Testing
@testable import HarkCore

private let stopPort = Routine(
    name: "stop port", steps: [Step(shell: "lsof -ti :{arg} | xargs kill", destructive: true)])
private let branches = Routine(name: "branches", steps: [Step(shell: "git -C {repo} branch --show-current")])
private let pullAll = Routine(name: "pull all", steps: [Step(shell: "git -C {repo} pull --ff-only", destructive: true)])
private let isItUp = Routine(name: "Is it up", steps: [Step(shell: "curl -s http://localhost:{arg}")])
private let startDay = Routine(
    name: "start my day", steps: [Step(say: "open the projects folder in VS Code"), Step(shell: "date")])
private let all = [stopPort, branches, pullAll, isItUp, startDay]
private let repos = ["~/Projects/shop-frontend", "/work/Shop-backend"]

@Test func aRoutineIsFoundByItsNameWithOrWithoutRun() {
    #expect(Routines.find(in: "pull all", among: all) == RoutineCall(routine: pullAll))
    #expect(Routines.find(in: "Run pull all.", among: all) == RoutineCall(routine: pullAll))
    #expect(Routines.find(in: "can you run the branches please", among: all) == RoutineCall(routine: branches))
    #expect(Routines.find(in: "Start the day", among: all) == RoutineCall(routine: startDay))
    #expect(Routines.find(in: "switch to Chrome", among: all) == nil)
}

@Test func aNameThatStartsWithRunIsStillFound() {
    let runTests = Routine(name: "run tests", steps: [Step(shell: "date")])
    #expect(Routines.find(in: "run tests", among: [runTests]) == RoutineCall(routine: runTests))
    #expect(Routines.find(in: "run run tests", among: [runTests]) == RoutineCall(routine: runTests))
}

@Test func wordsAfterTheNameAreTheArgument() {
    #expect(Routines.find(in: "stop port 8002", among: all) == RoutineCall(routine: stopPort, argument: "8002"))
    #expect(Routines.find(in: "Run stop port 8002", among: all) == RoutineCall(routine: stopPort, argument: "8002"))
    #expect(Routines.find(in: "is it up 5173?", among: all) == RoutineCall(routine: isItUp, argument: "5173"))
    #expect(Routines.find(in: "stop port", among: all) == RoutineCall(routine: stopPort))
}

@Test func onlyARoutineThatUsesAnArgumentTakesWordsAfterItsName() {
    #expect(Routines.find(in: "pull all the tabs into one window", among: all) == nil)
    #expect(Routines.find(in: "branches tab", among: all) == nil)
}

@Test func theLongestMatchingNameWins() {
    let stop = Routine(name: "stop", steps: [Step(shell: "echo {arg}")])
    #expect(Routines.find(in: "stop port 8002", among: [stop, stopPort])?.routine == stopPort)
    #expect(Routines.find(in: "stop music", among: [stop, stopPort]) == RoutineCall(routine: stop, argument: "music"))
}

@Test func aHostileArgumentStaysData() {
    let hostile = "8002; rm -rf ~ $(whoami) `id`"
    let commands = Routines.commands(for: "lsof -ti :{arg} | xargs kill", argument: hostile, repos: [])
    #expect(commands == [
        ShellCommand(text: "lsof -ti :\"$HARK_ARG\" | xargs kill", environment: ["HARK_ARG": hostile], label: nil)
    ])
    #expect(commands.allSatisfy { !$0.text.contains("rm") && !$0.text.contains("whoami") })
}

@Test func aSpokenArgumentCarriesNoPunctuation() {
    let call = Routines.find(in: "stop port 8002; rm -rf ~", among: all)
    #expect(call == RoutineCall(routine: stopPort, argument: "8002 rm rf"))
}

@Test func aModelMayOnlyPassOnWordsTheUserSaid() throws {
    let said = "can you stop whatever is on port 8002"
    let call = try Routines.chosen(name: "Stop Port", argument: "8002", said: said, among: all)
    #expect(call == RoutineCall(routine: stopPort, argument: "8002"))
    #expect(throws: RoutineError("Hark only passes on words the user said.")) {
        try Routines.chosen(name: "stop port", argument: "8002; curl collector.example", said: said, among: all)
    }
    #expect(throws: RoutineError("There is no routine called tidy up.")) {
        try Routines.chosen(name: "tidy up", argument: nil, said: said, among: all)
    }
    #expect(try Routines.chosen(name: "branches", argument: "", said: said, among: all) == RoutineCall(routine: branches))
}

@Test func aRepoStepRepeatsForEachProject() {
    let commands = Routines.commands(for: "git -C {repo} branch --show-current", argument: nil, repos: repos)
    let home = NSString(string: "~").expandingTildeInPath
    #expect(commands == [
        ShellCommand(
            text: "git -C \"$HARK_REPO\" branch --show-current",
            environment: ["HARK_REPO": "\(home)/Projects/shop-frontend"], label: "shop-frontend"),
        ShellCommand(
            text: "git -C \"$HARK_REPO\" branch --show-current",
            environment: ["HARK_REPO": "/work/Shop-backend"], label: "Shop-backend"),
    ])
}

@Test func aStepMayUseBothTheArgumentAndTheProjects() {
    let commands = Routines.commands(for: "git -C {repo} switch {arg}", argument: "main", repos: ["/work/api"])
    #expect(commands == [
        ShellCommand(
            text: "git -C \"$HARK_REPO\" switch \"$HARK_ARG\"",
            environment: ["HARK_ARG": "main", "HARK_REPO": "/work/api"], label: "api")
    ])
}

@Test func aMissingArgumentIsRefusedInPlainWords() {
    #expect(throws: RoutineError("“stop port” needs something said after its name")) {
        try Routines.check(RoutineCall(routine: stopPort), repos: repos)
    }
    #expect(throws: Never.self) {
        try Routines.check(RoutineCall(routine: stopPort, argument: "8002"), repos: repos)
    }
}

@Test func aRoutineThatCannotRunSaysWhy() {
    #expect(throws: RoutineError("“branches” runs once for each project, and your settings list no projects")) {
        try Routines.check(RoutineCall(routine: branches), repos: [])
    }
    #expect(throws: RoutineError("“empty” has no steps yet")) {
        try Routines.check(RoutineCall(routine: Routine(name: "empty", steps: [])), repos: repos)
    }
    let both = Routine(name: "both", steps: [Step(shell: "date"), Step(say: "open Chrome", shell: "date")])
    #expect(throws: RoutineError("Step 2 of “both” needs either \"say\" or \"shell\", and only one of them")) {
        try Routines.check(RoutineCall(routine: both), repos: repos)
    }
}

@Test func theQuestionQuotesTheDestructiveCommand() {
    let stop = RoutineCall(routine: stopPort, argument: "8002")
    #expect(Routines.needsYes(stop))
    #expect(Routines.describe(stop, everyStep: false, repos: repos) == "Run “stop port” (lsof -ti :8002 | xargs kill)")

    let pull = RoutineCall(routine: pullAll)
    #expect(
        Routines.describe(pull, everyStep: false, repos: repos)
            == "Run “pull all” (git -C {repo} pull --ff-only, once for each of 2 projects)")

    let day = RoutineCall(routine: startDay)
    #expect(!Routines.needsYes(day))
    #expect(
        Routines.describe(day, everyStep: true, repos: repos)
            == "Run “start my day” (say “open the projects folder in VS Code”; date)")
}

@Test func aDryRunListsEachCommand() {
    #expect(
        Routines.dryRunText(for: RoutineCall(routine: pullAll), repos: repos)
            == "Would run pull all: git -C ~/Projects/shop-frontend pull --ff-only; git -C /work/Shop-backend pull --ff-only")
    #expect(
        Routines.dryRunText(for: RoutineCall(routine: startDay), repos: repos)
            == "Would run start my day: say “open the projects folder in VS Code”; date")
}

@Test func theResultIsTheNameAndTheLastLine() {
    #expect(Routines.lastLine(of: "HTTP check\n200\n\n  \n") == "200")
    #expect(Routines.lastLine(of: "") == "")
    #expect(Routines.lastLine(of: String(repeating: "x", count: 300)).count == 120)
    #expect(Routines.result(name: "is it up", line: "200") == "is it up: 200")
    #expect(Routines.result(name: "start my day", line: nil) == "Ran start my day")
    #expect(Routines.line(for: [("shop-frontend", "main"), ("Shop-backend", "")]) == "shop-frontend main, Shop-backend done")
    #expect(Routines.stopped(name: "pull all", step: 2, because: "in api, not a git repository")
        == "“pull all” stopped at step 2: in api, not a git repository")
}

@Test func aRoutineIsFoundHoweverStartingItIsWorded() {
    let routines = [
        Routine(name: "shop suite", steps: [Step(say: "open the projects folder")]),
        Routine(name: "start local", steps: [Step(shell: "echo up")]),
    ]
    #expect(Routines.find(in: "Run the entire shop suite.", among: routines)?.routine.name == "shop suite")
    #expect(Routines.find(in: "start the whole shop suite", among: routines)?.routine.name == "shop suite")
    #expect(Routines.find(in: "start local", among: routines)?.routine.name == "start local")
    #expect(Routines.find(in: "run the shop", among: routines) == nil)
}
