import Testing

@testable import HarkCore

@Suite struct AppActionTests {
    private let notes: [[String]] = [
        ["Notes", "About Notes"], ["Notes", "Quit Notes"],
        ["File", "New Note"], ["File", "New Folder"], ["File", "New Smart Folder"], ["File", "Close"],
        ["File", "Print…"], ["File", "Add Account…"],
        ["Edit", "Undo"], ["Edit", "Find…"], ["Format", "Bold"],
        ["View", "Show Attachments Browser"], ["Window", "Zoom"], ["Window", "Minimize"], ["View", "Zoom"],
    ]

    // MARK: Request

    @Test func splitsTheAppFromTheAction() {
        let request = AppAction.request(in: "Open Notes and create a new note.")
        #expect(request == AppActionRequest(app: "notes", action: "create a new note"))
        #expect(AppAction.request(in: "launch Safari then new window") == AppActionRequest(app: "safari", action: "new window"))
        #expect(AppAction.request(in: "switch to the Notes app and print")?.app == "the notes")
        #expect(AppAction.request(in: "open Visual Studio Code and new file")?.app == "visual studio code")
        #expect(AppAction.request(in: "open notes app and please make a note")?.action == "make a note")
    }

    @Test func plainOpensAndLongAppNamesAreNotRequests() {
        #expect(AppAction.request(in: "open Notes") == nil)
        #expect(AppAction.request(in: "close Notes and print") == nil)
        #expect(AppAction.request(in: "open one two three four and print") == nil)
        #expect(AppAction.request(in: "open Notes and") == nil)
    }

    // MARK: Menu choice

    @Test func createANewNoteIsFileNewNote() {
        #expect(AppAction.choose("create a new note", among: notes) == .item(["File", "New Note"]))
        #expect(AppAction.choose("make a note", among: notes) == .item(["File", "New Note"]))
    }

    @Test func shorterTitlesFitLongerRequests() {
        #expect(AppAction.choose("print", among: notes) == .item(["File", "Print…"]))
        #expect(AppAction.choose("print this page", among: notes) == .item(["File", "Print…"]))
        #expect(AppAction.choose("bold", among: notes) == .item(["Format", "Bold"]))
    }

    @Test func anExactTitleBeatsLongerOnes() {
        #expect(AppAction.choose("new folder", among: notes) == .item(["File", "New Folder"]))
    }

    @Test func twoCloseFitsAreReportedAsUnsure() {
        guard case .unsure(let options) = AppAction.choose("new", among: notes) else {
            Issue.record("expected an unsure choice")
            return
        }
        #expect(options.count >= 2)
        #expect(options.contains(["File", "New Note"]))
    }

    @Test func aShorterMatchingTitleBeatsALongerOne() {
        let finder: [[String]] = [
            ["File", "New Finder Window"], ["Go", "Enclosing Folder in New Window"],
            ["Finder", "Services", "New Warp Window Here"], ["File", "New Tab"],
        ]
        #expect(AppAction.choose("new window", among: finder) == .item(["File", "New Finder Window"]))
    }

    @Test func nothingLikeItMeansNone() {
        #expect(AppAction.choose("teleport", among: notes) == .none)
        #expect(AppAction.choose("", among: notes) == .none)
    }

    @Test func theSameTitleInTwoMenusIsOneChoice() {
        #expect(AppAction.choose("zoom", among: notes) == .item(["View", "Zoom"]))
    }

    @Test func quitIsFoundSoTheCallerCanRefuseIt() {
        #expect(AppAction.choose("quit", among: notes) == .item(["Notes", "Quit Notes"]))
    }

    @Test func aWeakOverlapIsNotEnough() {
        #expect(AppAction.choose("show me the quarterly report", among: notes) == .none)
    }
}
