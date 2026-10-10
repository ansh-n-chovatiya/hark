import AVFoundation
import Speech

extension AppleTranscriber {
    /// Runs a recorded file through the same recogniser the microphone uses.
    ///
    /// The audio is fed at the speed it was spoken, as the microphone would deliver it, and
    /// `ms` is the time from the last sample to the final text: the wait a user feels after
    /// releasing the key. The call therefore takes at least as long as the recording.
    public func transcribe(file: URL) async throws -> (text: String, ms: Double) {
        let model = try await prepareRecogniser()
        let audio: AVAudioFile
        do {
            audio = try AVAudioFile(forReading: file)
        } catch {
            throw SpeechError.unreadableAudio(error.localizedDescription)
        }
        let source = audio.processingFormat
        let converter = try BufferConverter(from: source, to: model.format)
        let chunkFrames = AVAudioFrameCount(source.sampleRate * Self.fileChunkSeconds)
        guard let chunk = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: chunkFrames) else {
            throw SpeechError.unreadableAudio("cannot allocate a read buffer")
        }

        let session = try await takeSession()
        defer { refillStandby() }

        let clock = ContinuousClock()
        let began = clock.now
        var framesSent: AVAudioFramePosition = 0
        while audio.framePosition < audio.length {
            try audio.read(into: chunk, frameCount: chunkFrames)
            if chunk.frameLength == 0 { break }
            session.append(AnalyzerInput(buffer: try converter.convert(chunk)))
            framesSent += AVAudioFramePosition(chunk.frameLength)
            try await clock.sleep(until: began + .seconds(Double(framesSent) / source.sampleRate))
        }

        let released = clock.now
        let text = try await session.finish()
        let waited = clock.now - released
        return (text, Double(waited.components.seconds) * 1000 + Double(waited.components.attoseconds) / 1e15)
    }

    private static let fileChunkSeconds = 0.02
}
