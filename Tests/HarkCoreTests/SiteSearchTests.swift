import Foundation
import Testing

@testable import HarkCore

@Suite struct SiteSearchTests {
    @Test func aNameBeforeSearchIsTheWhere() {
        let request = SiteSearch.request(in: "open youtube search imran hashmi")
        #expect(request == SiteSearchRequest(site: "youtube", query: "imran hashmi"))
        #expect(SiteSearch.request(in: "open some site and search for lo-fi beats")?.site == "some site")
        #expect(SiteSearch.request(in: "go to acme and search invoices")?.site == "acme")
    }

    @Test func aNameAfterSearchIsTheWhere() {
        #expect(SiteSearch.request(in: "search swift concurrency on github")?.site == "github")
        #expect(SiteSearch.request(in: "look up the python docs in stack overflow")?.query == "the python docs")
    }

    @Test func enginesAndPlainSearchesAreLeftToTheOtherRules() {
        #expect(SiteSearch.request(in: "search swift on google") == nil)
        #expect(SiteSearch.request(in: "open chrome and search the weather") == nil)
        #expect(SiteSearch.request(in: "open youtube") == nil)
        #expect(SiteSearch.request(in: "youtube imran hashmi") == nil)
    }

    private let page = #"""
        <html><head><link rel="stylesheet" href="/s.css">
        <link rel="search" type="application/opensearchdescription+xml" href="/opensearch?locale=en" title="Site">
        </head></html>
        """#

    @Test func theSearchDescriptionIsFoundFromThePage() {
        let link = OpenSearch.descriptionLink(inHTML: page, base: URL(string: "https://www.example.com/")!)
        #expect(link?.absoluteString == "https://www.example.com/opensearch?locale=en")
        #expect(OpenSearch.descriptionLink(inHTML: "<html></html>", base: URL(string: "https://x.com")!) == nil)
    }

    @Test func theTemplateTakesTheHTMLAddress() {
        let xml = #"""
            <OpenSearchDescription>
            <Url type="application/x-suggestions+json" template="https://x.com/suggest?q={searchTerms}"/>
            <Url type="text/html" method="get" template="https://x.com/results?search_query={searchTerms}&amp;hl={language?}"/>
            </OpenSearchDescription>
            """#
        let template = OpenSearch.template(inXML: xml)
        #expect(template == "https://x.com/results?search_query={searchTerms}&hl={language?}")
        #expect(OpenSearch.address(template: template ?? "", query: "imran hashmi & co")?.absoluteString
                == "https://x.com/results?search_query=imran%20hashmi%20%26%20co")
    }

    @Test func aSiteOpenInATabCanAlwaysBeSearchedThroughGoogle() {
        let url = SiteSearch.limitedToSite("www.notion.so", query: "billing")
        #expect(url?.absoluteString.contains("site:www.notion.so") == true)
        #expect(SiteSearch.stem("www.notion.so") == "notion")
    }
}
