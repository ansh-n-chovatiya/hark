import Testing

@testable import HarkCore

@Suite struct FrontActionTests {
    @Test func bareActionsAreRequests() {
        #expect(FrontAction.request(in: "new window") == FrontActionRequest(phrase: "new window", opensSomething: false))
        #expect(FrontAction.request(in: "Print this.")?.phrase == "print this")
        #expect(FrontAction.request(in: "please zoom in")?.phrase == "zoom in")
    }

    @Test func openAndClickAreNotedAndRemoved() {
        #expect(FrontAction.request(in: "open my personal DM") == FrontActionRequest(phrase: "my personal dm", opensSomething: true))
        #expect(FrontAction.request(in: "click send")?.opensSomething == true)
        #expect(FrontAction.request(in: "go to settings")?.phrase == "settings")
    }

    @Test func hardsOwnVerbsAreLeftToTheirRules() {
        for phrase in ["close this tab", "quit slack", "paste", "undo that", "copy the address", "find the budget",
                       "switch to chrome", "delete it", "search for cats", "lock the screen", "set the volume to 30"] {
            #expect(FrontAction.request(in: phrase) == nil, "\(phrase)")
        }
    }

    @Test func emptyOrLongPhrasesAreNotRequests() {
        #expect(FrontAction.request(in: "") == nil)
        #expect(FrontAction.request(in: "open") == nil)
        #expect(FrontAction.request(in: "one two three four five six seven") == nil)
    }

    // MARK: Matching

    @Test func exactNeedsANearExactTitle() {
        let menu: [[String]] = [["File", "Print…"], ["File", "Print Preview"], ["File", "New Window"], ["View", "Zoom In"]]
        #expect(AppAction.exact("print this", among: menu) == ["File", "Print…"])
        #expect(AppAction.exact("new window", among: menu) == ["File", "New Window"])
        #expect(AppAction.exact("zoom in", among: menu) == ["View", "Zoom In"])
        #expect(AppAction.exact("preview", among: menu) == nil)
        #expect(AppAction.exact("make me a sandwich", among: menu) == nil)
    }

    @Test func aListItemIsFoundByAFewOfItsWords() {
        let labels = ["Chat", "Teams", "Personal DM, Hey are you free tonight, 4:10 PM", "Priya Sharma, Sent the file", "Calendar"]
        #expect(AppAction.chooseLabel("my personal dm", among: labels) == .label(2))
        #expect(AppAction.chooseLabel("calendar", among: labels) == .label(4))
        #expect(AppAction.chooseLabel("priya", among: labels) == .label(3))
        #expect(AppAction.chooseLabel("teleport", among: labels) == .none)
    }

    @Test func twoEquallyGoodLabelsAreUnsure() {
        let labels = ["Personal DM, Anna", "Personal DM, Ben", "Calendar"]
        guard case .unsure(let indexes) = AppAction.chooseLabel("personal dm", among: labels) else {
            Issue.record("expected unsure")
            return
        }
        #expect(Set(indexes) == [0, 1])
    }

    @Test func aOneWordTitleDoesNotWinAgainstALongRequest() {
        // "Add" reads as "new", but it is one word of a four-word request.
        let labels = ["Add", "Remove", "Not now", "Never"]
        #expect(AppAction.chooseLabel("make this window full size", among: labels) == .none)
        #expect(AppAction.chooseLabel("new window in chrome", among: labels) == .none)
        #expect(AppAction.chooseLabel("add", among: labels) == .label(0))
        #expect(AppAction.choose("print this page", among: [["File", "Print…"]]) == .item(["File", "Print…"]))
    }
}
