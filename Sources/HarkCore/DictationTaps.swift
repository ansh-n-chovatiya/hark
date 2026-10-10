import Foundation

/// Tells a hold from a double-tap on the dictation key. Hold the key and talk, as before. Or tap it twice
/// quickly to keep talking with no key held, and tap once more to finish. The decisions are made here, apart
/// from the keyboard, so they can be tested.
public struct DictationTaps: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case idle
        case holding
        /// A quick tap ended: waiting to see whether a second tap follows.
        case maybeDouble
        case handsFree
    }

    public enum Action: Sendable, Equatable {
        case start
        case becomeHandsFree
        case finish
        case cancel
        case wait
        case nothing
    }

    /// A press shorter than this is a tap.
    public static let tap: TimeInterval = 0.25
    /// A second tap must come within this long of the first.
    public static let doubleTapWindow: TimeInterval = 0.45

    public private(set) var mode = Mode.idle
    private var pressedAt: Date?

    public init() {}

    public mutating func keyDown(at now: Date) -> Action {
        switch mode {
        case .idle:
            mode = .holding
            pressedAt = now
            return .start
        case .maybeDouble:
            mode = .handsFree
            return .becomeHandsFree
        case .handsFree:
            mode = .idle
            return .finish
        case .holding:
            return .nothing
        }
    }

    public mutating func keyUp(at now: Date) -> Action {
        guard mode == .holding, let pressedAt else { return .nothing }
        if now.timeIntervalSince(pressedAt) < Self.tap {
            mode = .maybeDouble
            return .wait
        }
        mode = .idle
        return .finish
    }

    /// Called when the double-tap window has run out with no second tap.
    public mutating func windowClosed() -> Action {
        guard mode == .maybeDouble else { return .nothing }
        mode = .idle
        return .cancel
    }

    /// The recording was stopped some other way, such as the cancel button or a long recording.
    public mutating func reset() {
        mode = .idle
        pressedAt = nil
    }
}
