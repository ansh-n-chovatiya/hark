import Testing
@testable import HarkCore

private let parser = RuleParser(aliases: [
    "the backend": "Shop-backend",
    "standup notes": "~/Projects/standup.md",
])

private func parsed(_ transcript: String) -> Command? {
    parser.parse(transcript)
}

@Test(arguments: [
    ("Switch to Chrome.", "chrome"),
    ("Go to the render logs", "render logs"),
    ("Open Slack", "slack"),
    ("Show me the billing dashboard", "billing dashboard"),
    ("Find phase six recording", "phase 6 recording"),
    ("Hey, can you open Linear please?", "linear"),
])
func parserMapsOpenLeads(transcript: String, query: String) {
    let command = parsed(transcript)
    #expect(command?.verb == .open)
    #expect(command?.query == query)
    #expect(command?.kinds == [])
    #expect(command?.raw == transcript)
}

@Test func parserMapsClose() {
    #expect(parsed("Close the Linear tab") == Command(verb: .close, query: "linear", kinds: [.tab], raw: "Close the Linear tab"))
}

@Test(arguments: ["Close duplicate tabs", "close the duplicate tabs.", "Close duplicates", "Close all duplicate tabs"])
func parserMapsCloseDuplicates(transcript: String) {
    #expect(parsed(transcript) == Command(verb: .closeDuplicates, query: "", kinds: [.tab], raw: transcript))
}

@Test func parserMapsPasteWithOwner() {
    let command = parsed("Paste the link I copied from Teams")
    #expect(command?.verb == .paste)
    #expect(command?.query == "link")
    #expect(command?.owner == "teams")
    #expect(command?.kinds == [.clip])
}

@Test func parserMapsSave() {
    #expect(parsed("Save this as checkout plan") == Command(verb: .save, query: "checkout plan", raw: "Save this as checkout plan"))
}

@Test func parserKeepsFreeTextInSavedNames() {
    #expect(parsed("save this as work in progress tab")?.query == "work in progress tab")
    #expect(parsed("save this as work in progress tab")?.owner == nil)
}

@Test(arguments: ["Restore checkout plan", "Open workspace checkout plan", "restore the checkout plan workspace"])
func parserMapsRestore(transcript: String) {
    #expect(parsed(transcript) == Command(verb: .restore, query: "checkout plan", kinds: [.workspace], raw: transcript))
}

@Test func parserMapsHide() {
    #expect(parsed("Hide Slack") == Command(verb: .hide, query: "slack", raw: "Hide Slack"))
}

@Test func parserMapsRun() {
    #expect(parsed("Run morning setup") == Command(verb: .run, query: "morning setup", raw: "Run morning setup"))
}

@Test(arguments: ["Undo", "Undo that.", "undo that please"])
func parserMapsUndo(transcript: String) {
    #expect(parsed(transcript) == Command(verb: .undo, query: "", raw: transcript))
}

@Test(arguments: [
    ("One", "1"), ("two.", "2"), ("Three", "3"), ("four", "4"), ("Five", "5"),
    ("3", "3"), ("To", "2"), ("for", "4"), ("number two", "2"), ("the second", nil),
])
func parserMapsBareNumbersToPick(transcript: String, number: String?) {
    let command = parsed(transcript)
    if let number {
        #expect(command == Command(verb: .pick, query: number, raw: transcript))
    } else {
        #expect(command?.verb != .pick)
    }
}

@Test func parserTreatsSixAsADescription() {
    #expect(parsed("six")?.verb == .open)
    #expect(parsed("six")?.query == "6")
}

@Test(arguments: [
    ("the render logs tab", ItemKind.tab, "render logs"),
    ("the VS Code window for the backend", .window, "vs code shop-backend"),
    ("open the phase 6 recording file", .file, "phase 6 recording"),
    ("open the downloads folder", .file, "downloads"),
    ("switch to the Slack app", .app, "slack"),
    ("show the checkout plan workspace", .workspace, "checkout plan"),
])
func parserReadsKindWords(transcript: String, kind: ItemKind, query: String) {
    let command = parsed(transcript)
    #expect(command?.kinds == [kind])
    #expect(command?.query == query)
}

@Test func parserReadsOwnerPhrases() {
    #expect(parsed("open the pull request in Chrome")?.owner == "chrome")
    #expect(parsed("open the pull request in Chrome")?.query == "pull request")
    #expect(parsed("paste the address from Slack")?.owner == "slack")
    #expect(parsed("paste the thing I copied from V S Code")?.owner == "vs code")
    #expect(parsed("paste the thing I copied from V S Code")?.query == "thing")
    #expect(parsed("the relay window in VS Code") == Command(
        verb: .open, query: "relay", kinds: [.window], owner: "vs code", raw: "the relay window in VS Code"))
    #expect(parsed("open sign in")?.owner == nil)
    #expect(parsed("open sign in")?.query == "sign in")
}

@Test func parserAppliesAliases() {
    #expect(parsed("switch to the backend")?.query == "shop-backend")
    #expect(parsed("open standup notes")?.query == "~/projects/standup.md")
    #expect(parsed("paste the token I copied from the backend")?.owner == "shop-backend")
}

@Test(arguments: [
    ("switch to V S code", "vs code"),
    ("switch to versus code", "vs code"),
    ("Switch to VSCode", "vs code"),
    ("open visual studio code", "vs code"),
    ("open git hub", "github"),
    ("open you tube", "youtube"),
    ("go to local host", "localhost"),
    ("open chapter nine", "chapter 9"),
])
func parserNormalisesLooseSpellings(transcript: String, query: String) {
    #expect(parsed(transcript)?.query == query)
}

@Test func parserTreatsABareDescriptionAsOpen() {
    #expect(parsed("render logs") == Command(verb: .open, query: "render logs", raw: "render logs"))
}

@Test(arguments: ["", "   ", "...", "um, please"])
func parserReturnsNilForNothingSaid(transcript: String) {
    #expect(parsed(transcript) == nil)
}
