import Foundation
import Testing

@testable import HarkCore

@Suite struct DictationTapsTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    @Test func holdingAndReleasingFinishesAsBefore() {
        var taps = DictationTaps()
        #expect(taps.keyDown(at: at(0)) == .start)
        #expect(taps.keyUp(at: at(2)) == .finish)
        #expect(taps.mode == .idle)
    }

    @Test func aLoneQuickTapIsDiscarded() {
        var taps = DictationTaps()
        #expect(taps.keyDown(at: at(0)) == .start)
        #expect(taps.keyUp(at: at(0.1)) == .wait)
        #expect(taps.windowClosed() == .cancel)
        #expect(taps.mode == .idle)
    }

    @Test func twoQuickTapsGoHandsFreeAndOneMoreFinishes() {
        var taps = DictationTaps()
        _ = taps.keyDown(at: at(0))
        #expect(taps.keyUp(at: at(0.1)) == .wait)
        #expect(taps.keyDown(at: at(0.3)) == .becomeHandsFree)
        // Letting go of the second tap does nothing: the recording goes on.
        #expect(taps.keyUp(at: at(0.4)) == .nothing)
        #expect(taps.mode == .handsFree)
        // Minutes later, one tap ends it.
        #expect(taps.keyDown(at: at(60)) == .finish)
        #expect(taps.mode == .idle)
    }

    @Test func theWindowClosingAfterHandsFreeBeganDoesNothing() {
        var taps = DictationTaps()
        _ = taps.keyDown(at: at(0))
        _ = taps.keyUp(at: at(0.1))
        _ = taps.keyDown(at: at(0.2))
        #expect(taps.windowClosed() == .nothing)
        #expect(taps.mode == .handsFree)
    }

    @Test func aPressWhileHoldingChangesNothing() {
        var taps = DictationTaps()
        _ = taps.keyDown(at: at(0))
        #expect(taps.keyDown(at: at(0.5)) == .nothing)
    }

    @Test func resetReturnsToIdle() {
        var taps = DictationTaps()
        _ = taps.keyDown(at: at(0))
        _ = taps.keyUp(at: at(0.1))
        _ = taps.keyDown(at: at(0.2))
        taps.reset()
        #expect(taps.mode == .idle)
        #expect(taps.keyDown(at: at(5)) == .start)
    }

    @Test func aTapJustUnderTheLimitCountsAsATapAndJustOverAsAHold() {
        var quick = DictationTaps()
        _ = quick.keyDown(at: at(0))
        #expect(quick.keyUp(at: at(0.249)) == .wait)
        var slow = DictationTaps()
        _ = slow.keyDown(at: at(0))
        #expect(slow.keyUp(at: at(0.251)) == .finish)
    }
}
