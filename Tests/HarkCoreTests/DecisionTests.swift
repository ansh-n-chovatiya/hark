import Foundation
import Testing
@testable import HarkCore

private let parser = RuleParser(aliases: ["vs code": "code"])
private let desk: [Item] = [
    Item(id: "a1", kind: .app, title: "Google Chrome", detail: "Open"),
    Item(id: "a2", kind: .app, title: "Warp", detail: "Open"),
    Item(id: "a3", kind: .app, title: "Microsoft Teams", detail: "Open"),
    Item(id: "w1", kind: .window, title: "Acme Shop - Google Chrome", detail: "Google Chrome", owner: "Google Chrome"),
    Item(id: "w2", kind: .window, title: "claude", detail: "Warp", owner: "Warp"),
    Item(id: "t1", kind: .tab, title: "Acme Shop", detail: "localhost", owner: "Google Chrome"),
    Item(id: "t2", kind: .tab, title: "Acme Shop", detail: "localhost", owner: "Google Chrome"),
    Item(id: "t3", kind: .tab, title: "Screen Recorder - Record your screen", detail: "screenrecorder.io", owner: "Google Chrome"),
    Item(id: "t4", kind: .tab, title: "Karumi — AI Agent That Demos Your Product Live", detail: "karumi.ai", owner: "Google Chrome"),
]

private func decided(_ heard: String) -> Item? {
    guard let command = parser.parse(heard) else { return nil }
    let matches = rank(command, in: desk, now: Date())
    if isClear(matches) { return matches.first?.item }
    return obviousChoice(among: matches, kinds: command.kinds)
}

@Test func sayingAnAppNameMeansTheApp() {
    #expect(decided("Open Chrome")?.id == "a1")
    #expect(decided("Switch to Chrome.")?.id == "a1")
}

@Test func aMisheardAppNameStillFindsTheApp() {
    #expect(decided("Go to VARP.")?.id == "a2")
}

@Test func identicalTabsAreNotWorthAQuestion() {
    #expect(decided("open the acme shop tab")?.kind == .tab)
}

@Test func aSpokenRelativeClauseStillFindsTheTab() {
    #expect(decided("Open the Chrome tab, which has a screen recorder open.")?.id == "t3")
}

@Test func quitNamesAnApp() {
    let command = parser.parse("Quit teams.")
    #expect(command?.verb == .quit)
    #expect(command?.kinds == [.app])
    #expect(decided("Quit teams.")?.id == "a3")
}

@Test func newTabPhrasings() {
    #expect(parser.parse("Open Chrome in a new tab")?.verb == .newTab)
    #expect(parser.parse("Open Chrome in a new tab")?.query == "")
    #expect(parser.parse("open a Chrome tab")?.verb == .newTab)
    #expect(parser.parse("new tab")?.verb == .newTab)
    #expect(parser.parse("open youtube in a new tab")?.query == "youtube")
    #expect(parser.parse("open the karumi tab")?.verb == .open)
}

@Test func webAddressGuesses() {
    #expect(webAddress(for: "") == nil)
    #expect(webAddress(for: "youtube")?.absoluteString == "https://www.youtube.com")
    #expect(webAddress(for: "karumi.ai")?.absoluteString == "https://karumi.ai")
    #expect(webAddress(for: "localhost:5173")?.absoluteString == "http://localhost:5173")
    #expect(webAddress(for: "swift actors")?.absoluteString == "https://www.google.com/search?q=swift%20actors")
}

@Test func deletingIsAlwaysTurnedAway() {
    for said in ["Empty the recycle bin.", "delete the standup file", "Erase everything in downloads", "move it to the trash"] {
        #expect(asksToDelete(said))
    }
    for said in ["close duplicate tabs", "remove duplicate tabs", "quit Teams", "close all VS Code windows", "open the trends tab"] {
        #expect(!asksToDelete(said))
    }
}

@Test func aWholeNameBeatsLongerNamesThatContainIt() {
    let apps = [
        Item(id: "1", kind: .app, title: "Code", detail: "Open"),
        Item(id: "2", kind: .app, title: "Claude Code URL Handler", detail: "Not open"),
        Item(id: "3", kind: .app, title: "Codex", detail: "Not open"),
    ]
    let command = parser.parse("Quit VS Code")
    #expect(command?.verb == .quit)
    let matches = rank(command!, in: apps, now: Date())
    let chosen = isClear(matches) ? matches.first?.item : obviousChoice(among: matches, kinds: command!.kinds, query: command!.query)
    #expect(chosen?.id == "1")
}

@Test func withSeparatesTheAppFromWhatToOpenInIt() {
    let command = parser.parse("Open VS Code with project directory")
    #expect(command?.verb == .open)
    #expect(command?.query == "project")
    #expect(command?.owner == "code")
    #expect(command?.kinds == [.file])
    #expect(asksForFolder("Open VS Code with project directory"))
    #expect(!asksForFolder("open the standup file"))
}

@Test func askingToRunAScriptIsRecognised() {
    #expect(asksToRunAScript("Uh run start.sh in projects directory in vscode terminal."))
    #expect(asksToRunAScript("execute the deploy script"))
    #expect(asksToRunAScript("run build.py"))
    #expect(!asksToRunAScript("run terminal in VS Code"))
    #expect(!asksToRunAScript("run pull all"))
    #expect(!asksToRunAScript("open start.sh"))
    #expect(!asksToRunAScript("start work"))
}
