import Foundation
import Testing
@testable import HarkCore

private func entry(verb: String, totalMs: Double) -> Timings {
    Timings(
        at: Date(timeIntervalSince1970: 1_800_000_000),
        raw: "switch to chrome",
        verb: verb,
        outcome: "done",
        transcribeMs: 1,
        parseMs: 2,
        matchMs: 3,
        actMs: 4,
        totalMs: totalMs
    )
}

@Test func logAppendsAndReadsBack() {
    let url = FileManager.default.temporaryDirectory.appending(path: "hark-tests-\(UUID().uuidString)/timings.jsonl")
    let log = TimingLog(url: url)
    log.append(entry(verb: "open", totalMs: 120))
    log.append(entry(verb: "paste", totalMs: 80))
    #expect(log.all() == [entry(verb: "open", totalMs: 120), entry(verb: "paste", totalMs: 80)])
}

@Test func medianIsPerVerb() {
    let url = FileManager.default.temporaryDirectory.appending(path: "hark-tests-\(UUID().uuidString)/timings.jsonl")
    let log = TimingLog(url: url)
    for value in [300.0, 100, 200, 400] { log.append(entry(verb: "open", totalMs: value)) }
    log.append(entry(verb: "paste", totalMs: 9000))
    #expect(log.medianTotalMs(verb: "open") == 250)
    #expect(log.medianTotalMs(verb: "close") == nil)
}

@Test func medianOfOddAndEmpty() {
    #expect(median([5, 1, 3]) == 3)
    #expect(median([]) == nil)
}

@Suite struct TimingsModelTests {
    @Test func theModelThatAnsweredSurvivesSavingAndOlderRecordsStillLoad() throws {
        let entry = Timings(
            at: Date(timeIntervalSince1970: 1_790_000_000), raw: "open slack", verb: nil, outcome: "done", transcribeMs: 0,
            parseMs: 0, matchMs: 0, actMs: 0, totalMs: 0, model: "Claude Code")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(Timings.self, from: encoder.encode(entry)).model == "Claude Code")
        let old = #"{"at":"2026-10-10T10:00:00Z","raw":"x","outcome":"done","transcribeMs":0,"parseMs":0,"matchMs":0,"actMs":0,"totalMs":0}"#
        #expect(try decoder.decode(Timings.self, from: Data(old.utf8)).model == nil)
    }
}
