import Foundation
import Testing

@testable import HarkCore

@Suite struct SiteSearchTests {
    private func found(_ text: String, hosts: [String] = []) -> SiteSearchRequest? {
        SiteSearch.request(in: text, openHosts: hosts)
    }

    @Test func aSiteNamedBeforeSearchIsSearchedThere() {
        let request = found("open youtube search imran hashmi")
        #expect(request?.site == "youtube")
        #expect(request?.query == "imran hashmi")
        #expect(request?.address?.absoluteString == "https://www.youtube.com/results?search_query=imran%20hashmi")
        #expect(found("open YouTube and search for lo-fi beats")?.query == "lo fi beats")
        #expect(found("youtube imran hashmi") == nil)
    }

    @Test func aSiteNamedAfterSearchIsSearchedThere() {
        #expect(found("search swift concurrency on github")?.site == "github")
        #expect(found("look up the python docs in stack overflow")?.query == "the python docs")
    }

    @Test func anOpenSiteWithoutASearchPageIsSearchedThroughGoogle() {
        let request = found("search billing on notion", hosts: ["www.notion.so"])
        #expect(request?.address?.absoluteString.contains("site:www.notion.so") == true || request?.address?.absoluteString.contains("site%3Awww.notion.so") == true)
        #expect(found("search billing on notion") == nil)
    }

    @Test func enginesAndUnknownNamesAreLeftToTheOtherRules() {
        #expect(found("search swift on google") == nil)
        #expect(found("open chrome and search the weather") == nil)
        #expect(found("search the budget in notes") == nil)
        #expect(found("open youtube") == nil)
    }
}
