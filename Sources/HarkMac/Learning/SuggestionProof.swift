import Foundation
import HarkCore

/// Shows that a suggested name works before anyone is asked about it. It adds the name to a copy of
/// the settings, turns every model off, and runs the words through Hark in a dry run, which changes
/// nothing. Only a name that makes Hark say what it would do is offered. Suggestions that are not
/// names (saved pages and routines) need no proof, because they are exact by construction.
public actor SuggestionProof {
    public static let shared = SuggestionProof()

    private var known: [String: Bool] = [:]

    public func works(_ suggestion: Suggestion, config: Config) async -> Bool {
        guard suggestion.kind == .name, let said = suggestion.said, let meant = suggestion.meant else { return true }
        let key = "\(said)>\(meant)"
        if let cached = known[key] { return cached }
        var trial = config
        trial.aliases[said] = meant
        // Rules alone have to make it work, so the answer is the same every time.
        trial.useModel = false
        trial.fallbackModel = ""
        let scratch = FileManager.default.temporaryDirectory.appending(path: "hark-proof.jsonl")
        let pipeline = Pipeline(
            config: trial, sources: Registry.sources(config: trial), log: TimingLog(url: scratch), dryRun: true)
        await pipeline.refreshSources()
        let worked: Bool
        if case .done(let text) = await pipeline.run(transcript: said, transcribeMs: 0) {
            worked = text.hasPrefix("Would")
        } else {
            worked = false
        }
        known[key] = worked
        return worked
    }

    public func verified(_ suggestions: [Suggestion], config: Config) async -> [Suggestion] {
        var kept: [Suggestion] = []
        for suggestion in suggestions where await works(suggestion, config: config) { kept.append(suggestion) }
        return kept
    }
}
