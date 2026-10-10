import AVFoundation
import Speech

public enum SpeechError: Error, LocalizedError, Sendable {
    case unavailable
    case localeUnsupported(String)
    case noAudioFormat
    case microphoneDenied
    case noMicrophone
    case notPrepared
    case notStarted
    case unreadableAudio(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: "On-device speech recognition is not available on this Mac."
        case .localeUnsupported(let id): "On-device speech recognition does not support \(id)."
        case .noAudioFormat: "The speech model reported no usable audio format."
        case .microphoneDenied: "Hark is not allowed to use the microphone."
        case .noMicrophone: "No microphone is connected."
        case .notPrepared: "prepare() must finish before start()."
        case .notStarted: "finish() was called without a running capture."
        case .unreadableAudio(let reason): "The audio could not be read: \(reason)"
        }
    }
}

struct SpeechModel: Sendable {
    let locale: Locale
    let format: AVAudioFormat
    /// Nil when the second recogniser that listens for names is not available on this Mac.
    let namesLocale: Locale?

    // Measured on this app's commands: `SpeechTranscriber` ignores contextual strings in every
    // locale, and `DictationTranscriber` honours them in en_US but barely in en_IN.
    private static let preferredNamesLocale = Locale(identifier: "en_US")

    static func module(for locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
    }

    static func namesModule(for locale: Locale) -> DictationTranscriber {
        DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
    }

    static func load(
        preferred: Locale,
        onDownloadProgress: (@Sendable (Double) -> Void)?
    ) async throws -> SpeechModel {
        guard SpeechTranscriber.isAvailable else { throw SpeechError.unavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: preferred) else {
            throw SpeechError.localeUnsupported(preferred.identifier)
        }
        let module = module(for: locale)
        try await install([module], onDownloadProgress: onDownloadProgress)
        if let namesLocale = await installedNamesLocale(onDownloadProgress: onDownloadProgress),
           let shared = await SpeechAnalyzer.bestAvailableAudioFormat(
               compatibleWith: [module, namesModule(for: namesLocale)]
           ) {
            return SpeechModel(locale: locale, format: shared, namesLocale: namesLocale)
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw SpeechError.noAudioFormat
        }
        return SpeechModel(locale: locale, format: format, namesLocale: nil)
    }

    private static func installedNamesLocale(onDownloadProgress: (@Sendable (Double) -> Void)?) async -> Locale? {
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: preferredNamesLocale) else {
            return nil
        }
        // Names are an extra: a Mac that cannot install this model still transcribes without it.
        guard (try? await install([namesModule(for: locale)], onDownloadProgress: onDownloadProgress)) != nil else {
            return nil
        }
        return locale
    }

    private static func install(
        _ modules: [any SpeechModule],
        onDownloadProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        if await AssetInventory.status(forModules: modules) == .installed { return }
        // The first status query in a new process can answer "supported" for a model that is
        // already on disk, so ask once more before starting a download.
        if await AssetInventory.status(forModules: modules) == .installed { return }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else { return }

        let observation = request.progress.observe(\.fractionCompleted) { progress, _ in
            onDownloadProgress?(progress.fractionCompleted)
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
    }
}
