import AVFoundation
import FluidAudio
import HarkCore
import Synchronization

/// Speech to text with the Parakeet model running on this Mac.
///
/// Apple's recogniser still runs alongside: it supplies the live words shown while the key is
/// held, and its text is the answer whenever Parakeet cannot give one (its model is still
/// downloading on first run, the clip is too short, or it fails).
public final class ParakeetTranscriber: Transcriber {
    public var partials: AsyncStream<String> { apple.partials }

    private static let sampleRate = 16_000.0
    /// The model rejects anything shorter than about 0.3 s.
    private static let shortestClip = 0.4

    private let apple: AppleTranscriber
    private let engine = ParakeetEngine()
    private let onStatus: @Sendable (String) -> Void
    private let lastSource = Mutex("apple")

    /// `onStatus` reports model loading in words fit to show the user.
    public init(keepMicrophoneOpen: Bool = false, onStatus: @escaping @Sendable (String) -> Void = { _ in }) {
        apple = AppleTranscriber(keepMicrophoneOpen: keepMicrophoneOpen)
        self.onStatus = onStatus
    }

    /// Which engine produced the last transcript: "parakeet" or "apple".
    public var source: String { lastSource.withLock { $0 } }

    public func prepare() async throws {
        try await apple.prepare()
        // Not awaited: the first run downloads several hundred megabytes, and Hark should be
        // usable with Apple's recogniser meanwhile.
        Task { [engine, onStatus] in
            do {
                onStatus("Loading the speech model")
                try await engine.load()
                onStatus("")
            } catch {
                onStatus("The better speech model could not load: \(error.localizedDescription)")
            }
        }
    }

    public func setVocabulary(_ words: [String]) async {
        await apple.setVocabulary(words)
    }

    public func start() async throws {
        try await apple.start()
    }

    public func finish() async throws -> String {
        let fallback = try await apple.finish()
        let recording = apple.takeRecording()
        let seconds = Double(recording.samples.count) / max(recording.sampleRate, 1)
        guard recording.sampleRate == Self.sampleRate, seconds >= Self.shortestClip,
              let text = try? await engine.transcribe(recording.samples), !text.isEmpty
        else {
            lastSource.withLock { $0 = "apple" }
            return fallback
        }
        lastSource.withLock { $0 = "parakeet" }
        return text
    }

    /// Transcribes an audio file with Parakeet, for checking it without a microphone.
    public func transcribe(file: URL) async throws -> (text: String, ms: Double) {
        try await engine.load()
        let samples = try Self.samples(of: file)
        let clock = ContinuousClock()
        let started = clock.now
        let text = try await engine.transcribe(samples)
        let elapsed = clock.now - started
        return (text, Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
    }

    private static func samples(of file: URL) throws -> [Float] {
        let audio = try AVAudioFile(forReading: file)
        guard let wanted = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
            let source = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length))
        else { throw SpeechError.noAudioFormat }
        try audio.read(into: source)
        let converted = try BufferConverter(from: audio.processingFormat, to: wanted).convert(source)
        guard let channel = converted.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(converted.frameLength)))
    }
}

private actor ParakeetEngine {
    struct NotLoaded: Error {}

    private var manager: AsrManager?
    private var decoderLayers = 2
    private var loading: Task<Void, any Error>?

    func load() async throws {
        if manager != nil { return }
        if let loading { return try await loading.value }
        let task = Task {
            let models = try await AsrModels.downloadAndLoad(version: .v2)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            self.decoderLayers = await manager.decoderLayerCount
            self.manager = manager
        }
        loading = task
        defer { loading = nil }
        try await task.value
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager else { throw NotLoaded() }
        // The decoder carries state between calls, and each command must start clean.
        var state = TdtDecoderState.make(decoderLayers: decoderLayers)
        return try await manager.transcribe(samples, decoderState: &state).text
    }
}
