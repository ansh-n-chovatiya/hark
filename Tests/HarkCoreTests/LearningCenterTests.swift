import Foundation
import Testing

@testable import HarkCore

@Suite struct LearningCenterTests {
    private func makeCenter(_ folder: URL) -> LearningCenter {
        LearningCenter(
            activity: ActivityLog(url: folder.appending(path: "activity.jsonl")),
            history: TimingLog(url: folder.appending(path: "timings.jsonl")),
            store: LearningStore(url: folder.appending(path: "learning.json")))
    }

    private func temp() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "hark-learning-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private let nameSuggestion = Suggestion(
        id: "name:a>b", kind: .name, title: "t", detail: "d", said: "open slak", meant: "open slack")
    private let routineSuggestion = Suggestion(
        id: "routine:x", kind: .routine, title: "t", detail: "d", routineName: "morning",
        steps: ["open Slack", "open github", "quit Slack"], pages: ["github": "https://github.com"])

    @Test func acceptingANameAddsOnlyAnAliasAndRemovingTakesItBack() throws {
        let center = makeCenter(try temp())
        var config = Config()
        center.accept(nameSuggestion, into: &config)
        #expect(config.aliases == ["open slak": "open slack"])
        #expect(center.snapshot(config: config).accepted.count == 1)
        center.remove(nameSuggestion.id, from: &config)
        #expect(config.aliases.isEmpty)
        #expect(center.snapshot(config: config).accepted.isEmpty)
    }

    @Test func aLearnedRoutineKeepsOnlyOpenStepsAndSavesItsPages() throws {
        let center = makeCenter(try temp())
        var config = Config()
        center.accept(routineSuggestion, into: &config)
        #expect(config.routines.count == 1)
        #expect(config.routines[0].steps.compactMap(\.say) == ["open Slack", "open github"])
        #expect(config.routines[0].steps.allSatisfy { $0.shell == nil && !$0.destructive })
        #expect(config.links == ["github": "https://github.com"])
        center.remove(routineSuggestion.id, from: &config)
        #expect(config.routines.isEmpty)
        #expect(config.links.isEmpty)
    }

    @Test func removingLeavesAnythingTheUserChangedSince() throws {
        let center = makeCenter(try temp())
        var config = Config()
        center.accept(routineSuggestion, into: &config)
        config.links["github"] = "https://github.com/me"
        center.remove(routineSuggestion.id, from: &config)
        #expect(config.links["github"] == "https://github.com/me")
    }

    @Test func notNowHidesForTwoWeeksAndNeverHidesForGood() throws {
        let folder = try temp()
        let center = makeCenter(folder)
        let log = TimingLog(url: folder.appending(path: "timings.jsonl"))
        let now = Date()
        for (raw, outcome, offset) in [("Open Slak", "notUnderstood", -100.0), ("Open Slack", "done", -80.0)] {
            log.append(Timings(
                at: now.addingTimeInterval(offset), raw: raw, verb: nil, outcome: outcome, transcribeMs: 0, parseMs: 0,
                matchMs: 0, actMs: 0, totalMs: 0))
        }
        Thread.sleep(forTimeInterval: 0.2)
        let config = Config()
        let first = try #require(center.snapshot(config: config, now: now).suggestions.first)
        center.dismiss(first, forever: false, now: now)
        #expect(center.snapshot(config: config, now: now.addingTimeInterval(3600)).suggestions.isEmpty)
        #expect(center.snapshot(config: config, now: now.addingTimeInterval(15 * 86400)).suggestions.count == 1)
        center.dismiss(first, forever: true, now: now)
        #expect(center.snapshot(config: config, now: now.addingTimeInterval(400 * 86400)).suggestions.isEmpty)
    }

    @Test func nothingIsSuggestedWhileLearningIsOff() throws {
        let center = makeCenter(try temp())
        var config = Config()
        config.learns = false
        #expect(center.snapshot(config: config).suggestions.isEmpty)
        #expect(center.snapshot(config: config).deadEnds.isEmpty)
    }

    @Test func deleteAllEmptiesTheActivityFile() throws {
        let center = makeCenter(try temp())
        center.activity.append(ActivityEvent(at: Date(), kind: .app, name: "Slack"))
        #expect(center.activity.all().count == 1)
        center.deleteAll()
        #expect(center.activity.all().isEmpty)
    }

    @Test func oldRecordsAreDroppedAndTheFileIsPrivate() throws {
        let folder = try temp()
        let log = ActivityLog(url: folder.appending(path: "activity.jsonl"))
        let now = Date()
        log.append(ActivityEvent(at: now.addingTimeInterval(-100 * 86400), kind: .app, name: "Old"))
        log.append(ActivityEvent(at: now, kind: .app, name: "New"))
        log.prune(now: now)
        #expect(log.all().map(\.name) == ["New"])
        let mode = try FileManager.default.attributesOfItem(atPath: folder.appending(path: "activity.jsonl").path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func setupFindsProjectsOnceAndOnlyWhenNothingIsSet() throws {
        let home = try temp()
        let project = home.appending(path: "Projects/shop/.git")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let center = makeCenter(try temp())
        var config = Config()
        #expect(center.setUpIfNeeded(&config, home: home))
        #expect(config.searchFolders == ["~/Projects"])
        #expect(config.repos == ["~/Projects/shop"])
        var again = Config()
        #expect(!center.setUpIfNeeded(&again, home: home))
        #expect(again.repos.isEmpty)
    }

    @Test func setupLeavesWhatTheUserAlreadyChose() throws {
        let home = try temp()
        try FileManager.default.createDirectory(at: home.appending(path: "Code/app/.git"), withIntermediateDirectories: true)
        var config = Config(searchFolders: ["~/Mine"])
        #expect(!makeCenter(try temp()).setUpIfNeeded(&config, home: home))
        #expect(config.searchFolders == ["~/Mine"])
    }

    @Test func setupDoesNothingWhileLearningIsOff() throws {
        let home = try temp()
        try FileManager.default.createDirectory(at: home.appending(path: "Code/app/.git"), withIntermediateDirectories: true)
        var config = Config()
        config.learns = false
        #expect(!makeCenter(try temp()).setUpIfNeeded(&config, home: home))
        #expect(config.repos.isEmpty)
    }

    @Test func learningIsOnByDefaultAndOldConfigsStayOn() throws {
        #expect(Config().learns)
        #expect(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).learns)
    }
}
