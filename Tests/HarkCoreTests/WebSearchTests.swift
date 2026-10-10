import Testing

@testable import HarkCore

@Suite struct WebSearchTests {
    private func query(_ text: String) -> String? { WebSearch.request(in: text)?.query }

    @Test func searchOnGoogleTakesOffTheWebWords() {
        #expect(query("Search Shadow Khan on the Google.") == "shadow khan")
        #expect(query("search swift concurrency on google") == "swift concurrency")
        #expect(query("Search for the weather in Pune online") == "the weather in pune")
    }

    @Test func googleAndLookUpAreSearches() {
        #expect(query("google swift concurrency") == "swift concurrency")
        #expect(query("Look up the capital of Peru") == "the capital of peru")
    }

    @Test func openChromeAndSearchOpensInChrome() throws {
        let request = try #require(WebSearch.request(in: "Open Chrome and search Jantar Mantar in new tab."))
        #expect(request.query == "jantar mantar")
        #expect(request.inChrome)
        #expect(request.address?.absoluteString == "https://www.google.com/search?q=jantar%20mantar")
    }

    @Test func aPlainSearchIsAWebSearchUnlessItIsAboutFiles() {
        #expect(query("search the random words one, two, three") == "the random words one two three")
        #expect(query("search for files named budget") == nil)
        #expect(query("search my downloads folder for invoices") == nil)
        #expect(query("search my project for TODO") == nil)
    }

    @Test func nothingToSearchForIsNotASearch() {
        #expect(query("search") == nil)
        #expect(query("search something") == nil)
        #expect(query("open chrome and search anything") == nil)
        #expect(query("google") == nil)
    }

    @Test func otherCommandsAreLeftAlone() {
        #expect(query("open chrome") == nil)
        #expect(query("switch to the google doc") == nil)
        #expect(query("find the budget spreadsheet") == nil)
    }

    @Test func aMisheardTriggerIsNotGuessedAt() {
        #expect(query("surge shadow khan") == nil)
    }

    @Test func characterThatCouldChangeTheAddressAreEncoded() throws {
        let request = try #require(WebSearch.request(in: "search a&b=c on google"))
        #expect(request.address?.absoluteString.contains("&b=c") == false)
    }
}
