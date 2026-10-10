import AVFoundation
import os

/// How loud the microphone is right now, from 0 to 1, for the dictation indicator's waveform. The
/// audio thread writes it and the screen reads it, so it holds one number behind a lock and nothing
/// of what was said.
public enum MicrophoneLevel {
    private static let value = OSAllocatedUnfairLock(initialState: Float(0))

    public static var current: Float { value.withLock { $0 } }

    static func update(from buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let level = min(1, (sum / Float(buffer.frameLength)).squareRoot() * 10)
        // Rises at once and falls away over a few buffers, so the bars do not flicker.
        value.withLock { $0 = max(level, $0 * 0.6) }
    }

    static func reset() { value.withLock { $0 = 0 } }
}
