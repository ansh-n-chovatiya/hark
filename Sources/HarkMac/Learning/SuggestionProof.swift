import Foundation
import HarkCore

/// Shows that a suggested name helps before anyone is asked about it. It runs the whole command that failed
/// through Hark twice with every model off, in a dry run that changes nothing: once as things are, once with the
/// name added. Only a name that turns a command Hark did not understand into one it would act on is offered.
/// A name that points at something Hark cannot match, or a command that already works, is dropped. Suggestions
/// that are not names (saved pages and routines) need no proof, because they are exact by construction.
public actor SuggestionProof {
    public static let shared = SuggestionProof()

    private var known: [String: Bool] = [:]

    public func works(_ suggestion: Suggestion, config: Config) async -> Bool {
        guard suggestion.kind == .name, let said = suggestion.said, let meant = suggestion.meant else { return true }
        let key = "\(said)>\(meant)"
        if let cached = known[key] { return cached }
        let phrase = suggestion.example ?? said
        // Rules alone have to decide, so the answer is the same every time.
        var plain = config
        plain.useModel = false
        plain.fallbackModel = ""
        plain.aliases[said] = nil
        var trial = plain
        trial.aliases[said] = meant
        // It has to fail now and work with the name. A phrase that already works needs no name.
        let alreadyWorks = await Self.wouldAct(on: phrase, with: plain)
        let worked = alreadyWorks ? false : await Self.wouldAct(on: phrase, with: trial)
        known[key] = worked
        return worked
    }

    public func verified(_ suggestions: [Suggestion], config: Config) async -> [Suggestion] {
        var kept: [Suggestion] = []
        for suggestion in suggestions where await works(suggestion, config: config) { kept.append(suggestion) }
        return kept
    }

    /// Runs the words through Hark in a dry run, which changes nothing, and says whether it would act.
    private static func wouldAct(on phrase: String, with config: Config) async -> Bool {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "hark-proof.jsonl")
        let pipeline = Pipeline(
            config: config, sources: Registry.sources(config: config), log: TimingLog(url: scratch), dryRun: true)
        await pipeline.refreshSources()
        let outcome = await pipeline.run(transcript: phrase, transcribeMs: 0)
        if ProcessInfo.processInfo.environment["HARK_DEBUG_PROOF"] != nil { print("proof outcome:", outcome) }
        if case .done(let text) = outcome { return text.hasPrefix("Would") }
        return false
    }
}
