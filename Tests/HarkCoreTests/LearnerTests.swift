import Foundation
import Testing

@testable import HarkCore

@Suite struct LearnerTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private static let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func entry(_ raw: String, _ outcome: String, at seconds: Double, summary: String? = nil) -> Timings {
        Timings(
            at: Self.start.addingTimeInterval(seconds), raw: raw, verb: nil, outcome: outcome, transcribeMs: 0,
            parseMs: 0, matchMs: 0, actMs: 0, totalMs: 0, summary: summary)
    }

    private func event(_ kind: ActivityEvent.Kind, _ name: String, day: Int, hour: Int = 9, minute: Int = 0) -> ActivityEvent {
        let base = Self.calendar.startOfDay(for: Self.start)
        let date = Self.calendar.date(byAdding: .day, value: day, to: base)!
            .addingTimeInterval(Double(hour * 3600 + minute * 60))
        return ActivityEvent(at: date, kind: kind, name: name)
    }

    // MARK: Misheard words

    @Test func aFailedCommandFollowedByASimilarWorkingOneIsOffered() {
        let history = [
            entry("Open Slak", "notUnderstood", at: 0),
            entry("Open Slack", "done", at: 20),
        ]
        let found = Learner.names(history: history, config: Config())
        #expect(found.count == 1)
        #expect(found[0].said == "slak")
        #expect(found[0].meant == "slack")
        #expect(found[0].example == "open slak")
    }

    @Test func aPairSeenOnceThatIsNotVeryAlikeWaitsForASecondSighting() {
        let once = [entry("jantar", "notUnderstood", at: 0), entry("open the planner", "done", at: 20)]
        #expect(Learner.names(history: once, config: Config()).isEmpty)
    }

    @Test func unrelatedRetriesAreNotPaired() {
        let history = [entry("Hello", "notUnderstood", at: 0), entry("lock the screen", "done", at: 20)]
        #expect(Learner.names(history: history, config: Config()).isEmpty)
    }

    @Test func aSuccessAfterTheWindowIsNotPaired() {
        let history = [entry("Open Slak", "notUnderstood", at: 0), entry("Open Slack", "done", at: 200)]
        #expect(Learner.names(history: history, config: Config()).isEmpty)
    }

    @Test func aNameTheUserAlreadyHasIsNotOfferedAgain() {
        let history = [entry("Open Slak", "notUnderstood", at: 0), entry("Open Slack", "done", at: 20)]
        let config = Config(aliases: ["slak": "slack"])
        #expect(Learner.names(history: history, config: config).isEmpty)
    }

    @Test func refusalsAreNeverLearnedFrom() {
        let history = [
            entry("Empty recycle bin", "failed", at: 0, summary: "Hark does not delete anything"),
            entry("Empty recycle bin now", "done", at: 10),
        ]
        #expect(Learner.names(history: history, config: Config()).isEmpty)
        #expect(Learner.deadEnds(history: history).isEmpty)
    }

    // MARK: Web pages

    @Test func aSiteOnThreeDaysIsOffered() {
        let activity = (0..<3).map { event(.site, "github.com", day: $0) }
        let found = Learner.pages(activity: activity, config: Config(), calendar: Self.calendar)
        #expect(found.count == 1)
        #expect(found[0].pageName == "github")
        #expect(found[0].address == "https://github.com")
    }

    @Test func manyVisitsOnOneDayAreNotEnough() {
        let activity = (0..<10).map { event(.site, "github.com", day: 0, minute: $0) }
        #expect(Learner.pages(activity: activity, config: Config(), calendar: Self.calendar).isEmpty)
    }

    @Test func aSavedPageIsNotOfferedAgainAndLocalAddressesAreIgnored() {
        let activity = (0..<3).flatMap { [event(.site, "www.github.com", day: $0), event(.site, "localhost", day: $0)] }
        let config = Config(links: ["code": "https://github.com/me"])
        #expect(Learner.pages(activity: activity, config: config, calendar: Self.calendar).isEmpty)
    }

    @Test func pageNamesDropTheEndingAndWww() {
        #expect(Learner.pageName(forHost: "www.github.com") == "github")
        #expect(Learner.pageName(forHost: "mail.google.com") == "mail google")
        #expect(Learner.pageName(forHost: "news.bbc.co.uk") == "news bbc")
    }

    // MARK: Repeated chores

    @Test func sameStartOnThreeDaysMakesAnOpenOnlyRoutine() {
        var activity: [ActivityEvent] = []
        for day in 0..<3 {
            activity += [
                event(.app, "Slack", day: day, minute: 0), event(.app, "Linear", day: day, minute: 2),
                event(.site, "github.com", day: day, minute: 4),
                // Later the same day, a different session that must not count.
                event(.app, "Spotify", day: day, hour: 15),
            ]
        }
        let found = Learner.routines(activity: activity, config: Config(), calendar: Self.calendar)
        #expect(found.count == 1)
        #expect(found[0].routineName == "morning")
        #expect(found[0].steps == ["open Linear", "open Slack", "open github"])
        #expect(found[0].pages == ["github": "https://github.com"])
        #expect(found[0].steps?.allSatisfy { $0.hasPrefix("open ") } == true)
    }

    @Test func twoDaysIsNotARoutine() {
        let activity = (0..<2).flatMap { [event(.app, "Slack", day: $0), event(.app, "Linear", day: $0, minute: 1)] }
        #expect(Learner.routines(activity: activity, config: Config(), calendar: Self.calendar).isEmpty)
    }

    @Test func hark_finder_and_system_apps_are_left_out() {
        let activity = (0..<3).flatMap { [event(.app, "Hark", day: $0), event(.app, "Finder", day: $0, minute: 1)] }
        #expect(Learner.routines(activity: activity, config: Config(), calendar: Self.calendar).isEmpty)
    }

    @Test func aTakenRoutineNameGetsANumber() {
        let activity = (0..<3).flatMap { [event(.app, "Slack", day: $0), event(.app, "Linear", day: $0, minute: 1)] }
        let config = Config(routines: [Routine(name: "morning", steps: [Step(say: "lock the screen")])])
        let found = Learner.routines(activity: activity, config: config, calendar: Self.calendar)
        #expect(found.first?.routineName == "morning 2")
    }

    // MARK: Dead ends

    @Test func deadEndsAreCountedAndTagged() {
        let history = [
            entry("search for swift", "notUnderstood", at: 0), entry("search for swift", "notUnderstood", at: 500),
            entry("Hello", "notUnderstood", at: 900),
        ]
        let found = Learner.deadEnds(history: history)
        #expect(found.count == 1)
        #expect(found[0].count == 2)
        #expect(found[0].topic == "Searching the web")
    }

    @Test func similarityIsOneForSameAndLowForDifferent() {
        #expect(Learner.similarity("open slack", "open slack") == 1)
        #expect(Learner.similarity("abc", "xyz") == 0)
    }

    // MARK: What a pair teaches

    @Test func aNameKeepsOnlyTheThingNamed() {
        #expect(Learner.alias(said: "open slak", meant: "open slack")?.said == "slak")
        #expect(Learner.alias(said: "switch to the linier", meant: "switch to linear")?.meant == "linear")
        #expect(Learner.alias(said: "open new warp terminal", meant: "open warp")?.said == "new warp terminal")
        #expect(Learner.alias(said: "MT recycle B", meant: "empty recycle bin")?.said == "mt recycle b")
    }

    @Test func pairsWithDifferentVerbsOrNothingLeftTeachNothing() {
        #expect(Learner.alias(said: "open slack", meant: "close slack") == nil)
        #expect(Learner.alias(said: "open slack", meant: "slack") == nil)
        #expect(Learner.alias(said: "open the slack", meant: "open slack") == nil)
        #expect(Learner.alias(said: "open", meant: "open slack") == nil)
    }
}
