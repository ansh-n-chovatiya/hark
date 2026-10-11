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
