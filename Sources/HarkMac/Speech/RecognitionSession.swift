import AVFoundation
import Speech
import Synchronization

/// One utterance. An analyzer cannot be reused after it is finished, so each command gets its own.
final class RecognitionSession: Sendable {
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let collector: Task<String, any Error>
    private let namesCollector: Task<String, Never>?
    private let vocabulary = Mutex<[String]>([])

    init(model: SpeechModel, onPartial: @escaping @Sendable (String) -> Void) async throws {
        let transcriber = SpeechModel.module(for: model.locale)
        let namesTranscriber = model.namesLocale.map(SpeechModel.namesModule)
        let modules: [any SpeechModule] = if let namesTranscriber { [transcriber, namesTranscriber] } else { [transcriber] }
        let analyzer = SpeechAnalyzer(
            modules: modules,
            // Keeps the model in memory between commands, so only the first session pays to load it.
            options: .init(priority: .userInitiated, modelRetention: .processLifetime)
        )
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.prepareToAnalyze(in: model.format)
        try await analyzer.start(inputSequence: stream)

        self.analyzer = analyzer
        self.input = continuation
        self.collector = Task {
            var settled = ""
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                if result.isFinal {
                    settled += text
                    onPartial(settled)
                } else {
                    onPartial(settled + text)
                }
            }
            return settled.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.namesCollector = namesTranscriber.map { namesTranscriber in
            Task {
                var settled = ""
                // A failure here only costs the name corrections; the main transcript still stands.
                do {
                    for try await result in namesTranscriber.results where result.isFinal {
                        settled += String(result.text.characters)
                    }
                } catch {
                    return ""
                }
                return settled
            }
        }
    }

    /// Tells the recogniser which names to expect. It only affects audio appended after this
    /// returns, and costs about 2 ms per string, so it belongs in the idle time between commands.
    func setVocabulary(_ words: [String]) async {
        guard namesCollector != nil, vocabulary.withLock({ $0 != words }) else { return }
        let context = AnalysisContext()
        context.contextualStrings[.general] = words
        do {
            try await analyzer.setContext(context)
        } catch {
            return
        }
        vocabulary.withLock { $0 = words }
    }

    func append(_ audio: AnalyzerInput) {
        input.yield(audio)
    }

    func finish() async throws -> String {
        input.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await collector.value
        let words = vocabulary.withLock { $0 }
        guard let namesCollector, !words.isEmpty else { return text }
        return restoreNames(in: text, from: await namesCollector.value, vocabulary: words)
    }
}
