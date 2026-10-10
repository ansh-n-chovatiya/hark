import AVFoundation
import Speech

final class MicrophoneInput: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let target: AVAudioFormat
    private let sink: @Sendable (AnalyzerInput) -> Void
    private let queue = DispatchQueue(label: "hark.microphone")
    private var wanted = false
    private var observer: (any NSObjectProtocol)?

    init(target: AVAudioFormat, sink: @escaping @Sendable (AnalyzerInput) -> Void) {
        self.target = target
        self.sink = sink
        // The engine stops itself when the input device changes (headphones plugged in, a
        // different microphone chosen) and has to be started again with the new device's format.
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            queue.async { self.restartAfterDeviceChange() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    static func requestAccess() async throws {
        switch Permissions.status(.microphone) {
        case .granted: return
        case .notAsked:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw SpeechError.microphoneDenied }
        case .denied: throw SpeechError.microphoneDenied
        }
    }

    func start() throws {
        try queue.sync {
            wanted = true
            try startEngine()
        }
    }

    func stop() {
        queue.sync {
            wanted = false
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    private func startEngine() throws {
        guard !engine.isRunning else { return }
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechError.noMicrophone }
        let converter = try BufferConverter(from: format, to: target)
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { [sink] buffer, _ in
            // A tap has nowhere to throw; a buffer that fails to convert is dropped and shows up
            // as missing words rather than stopping capture.
            guard let converted = try? converter.convert(buffer) else { return }
            sink(AnalyzerInput(buffer: converted))
        }
        engine.prepare()
        try engine.start()
    }

    private func restartAfterDeviceChange() {
        guard wanted else { return }
        // If this fails the engine stays stopped, and the next start() reports the error.
        try? startEngine()
    }
}
