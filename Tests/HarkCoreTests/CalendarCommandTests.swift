import Foundation
import Testing

@testable import HarkCore

@Suite struct CalendarCommandTests {
    @Test func calendarQuestions() {
        #expect(CalendarCommand.parse("what's next") == .next)
        #expect(CalendarCommand.parse("What's my day look like?") == .today)
        #expect(CalendarCommand.parse("join my next meeting") == .join)
        #expect(CalendarCommand.parse("am I free at 3 pm") == .free(hour: 15, minute: 0))
        #expect(CalendarCommand.parse("am I free at 3") == .free(hour: 15, minute: 0))
        #expect(CalendarCommand.parse("am I free at 10 30") == .free(hour: 10, minute: 30))
        #expect(CalendarCommand.parse("open slack") == nil)
    }

    @Test func theFirstLinkInAnEventIsFound() {
        let link = CalendarCommand.firstLink(in: [nil, "Room 4", "Agenda\nJoin: https://meet.example.com/abc-def?x=1 thanks"])
        #expect(link?.absoluteString == "https://meet.example.com/abc-def?x=1")
        #expect(CalendarCommand.firstLink(in: ["no link here"]) == nil)
    }
}

@Suite struct DocumentQueryTests {
    private let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .gmt; return c }()
    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    @Test func nameKindAndDateAreSeparated() {
        let now = at("2026-10-11T12:00:00Z") // a Sunday
        let query = DocumentQuery.parse("open the budget spreadsheet I worked on Tuesday", now: now, calendar: calendar)
        #expect(query?.nameWords == ["budget"])
        #expect(query?.kind == "public.spreadsheet")
        #expect(query?.since == at("2026-10-06T00:00:00Z"))
        #expect(query?.until == at("2026-10-07T00:00:00Z"))
        #expect(query?.spotlight.contains("kMDItemFSName == \"*budget*\"cd") == true)
    }

    @Test func aDateIsRequired() {
        #expect(DocumentQuery.parse("open the budget spreadsheet") == nil)
        #expect(DocumentQuery.parse("find my contract pdf from last week")?.kind == "com.adobe.pdf")
    }
}
