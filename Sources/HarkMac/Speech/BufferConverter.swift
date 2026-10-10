import AVFoundation

/// Converts a stream of buffers to the speech model's format. Not thread-safe: one instance
/// belongs to one producer (the microphone tap or one file read).
final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private let ratio: Double

    init(from source: AVAudioFormat, to target: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: source, to: target) else {
            throw SpeechError.unreadableAudio("cannot convert \(source) to \(target)")
        }
        self.converter = converter
        self.target = target
        self.ratio = target.sampleRate / source.sampleRate
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw SpeechError.unreadableAudio("cannot allocate a buffer of \(capacity) frames")
        }
        var handedOver = false
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, inputStatus in
            if handedOver {
                inputStatus.pointee = .noDataNow
                return nil
            }
            handedOver = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            throw SpeechError.unreadableAudio(failure?.localizedDescription ?? "conversion failed")
        }
        return output
    }
}
