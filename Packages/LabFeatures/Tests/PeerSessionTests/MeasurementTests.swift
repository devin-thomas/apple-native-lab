import Foundation
@testable import PeerSession
import Testing

/// LAB-019: clock error, sequence gaps, and presence, measured from injected clocks.
@Suite struct MeasurementTests {
    @Test func theEstimateFindsAKnownOffsetWithinItsUncertainty() {
        var estimator = ClockEstimator()
        // The remote clock reads 250 ms ahead. Round trips take 20, 4, and 60 ms, split unevenly.
        let offset: Int64 = 250_000_000
        for (t0, up, down) in [(Int64(0), Int64(15_000_000), Int64(5_000_000)), (1_000_000_000, 2_000_000, 2_000_000), (2_000_000_000, 10_000_000, 50_000_000)] {
            let t1 = t0 + up + offset
            let t2 = t1 + 1_000_000
            let t3 = t2 - offset + down
            estimator.add(sent: PeerInstant(nanoseconds: t0), received: PeerInstant(nanoseconds: t1),
                          answered: PeerInstant(nanoseconds: t2), returned: PeerInstant(nanoseconds: t3))
        }
        let estimate = try! #require(estimator.estimate)
        #expect(estimate.roundTrip == .milliseconds(4))
        #expect(estimate.uncertainty == .milliseconds(2))
        #expect(abs((estimate.offset - .milliseconds(250)).wholeNanoseconds) <= estimate.uncertainty.wholeNanoseconds)
        #expect(estimate.sampleCount == 3)
        #expect(estimate.age(at: PeerInstant(nanoseconds: 3_000_000_000)) > .zero)
        #expect(estimate.localInstant(forRemote: PeerInstant(nanoseconds: 1_250_000_000)) == PeerInstant(nanoseconds: 1_000_000_000))

        // Inconsistent readings are refused, not averaged in.
        estimator.add(sent: PeerInstant(nanoseconds: 10), received: PeerInstant(nanoseconds: 50), answered: PeerInstant(nanoseconds: 40), returned: PeerInstant(nanoseconds: 20))
        #expect(estimator.rejected == 1)
        estimator.reset()
        #expect(estimator.estimate == nil)
    }

    @Test func theWindowKeepsOnlyRecentRoundTrips() {
        var estimator = ClockEstimator()
        // One excellent early round trip, then many ordinary ones: it ages out of the window.
        estimator.add(sent: .init(nanoseconds: 0), received: .init(nanoseconds: 1), answered: .init(nanoseconds: 1), returned: .init(nanoseconds: 2))
        for index in 1...ClockEstimator.window {
            let t0 = Int64(index) * 1_000_000_000
            estimator.add(sent: .init(nanoseconds: t0), received: .init(nanoseconds: t0 + 5_000_000),
                          answered: .init(nanoseconds: t0 + 5_000_000), returned: .init(nanoseconds: t0 + 10_000_000))
        }
        #expect(estimator.estimate?.roundTrip == .milliseconds(10))
        #expect(estimator.estimate?.sampleCount == ClockEstimator.window)
    }

    @Test func sequenceGapsAndStaleNumbersAreCounted() {
        var tracker = SequenceTracker()
        #expect(tracker.observe(1) == .inOrder)
        #expect(tracker.observe(2) == .inOrder)
        #expect(tracker.observe(5) == .gap(missing: 2))
        #expect(tracker.observe(4) == .stale)
        #expect(tracker.observe(5) == .stale)
        #expect(tracker.observe(6) == .inOrder)
        #expect(tracker.gaps == 1 && tracker.missing == 2 && tracker.stale == 2 && tracker.last == 6)
    }

    @Test func presenceGoesStaleThenDisconnected() {
        let timing = SessionTiming(staleAfter: .seconds(2), disconnectAfter: .seconds(8))
        let heard = PeerInstant(nanoseconds: 1_000_000_000)
        #expect(timing.presence(lastHeard: heard, now: heard.advanced(by: .seconds(2))) == .live)
        #expect(timing.presence(lastHeard: heard, now: heard.advanced(by: .milliseconds(2_001))) == .stale(since: heard.advanced(by: .seconds(2))))
        #expect(timing.presence(lastHeard: heard, now: heard.advanced(by: .seconds(9))) == .disconnected(since: heard.advanced(by: .seconds(8))))
    }

    @Test func instantsSaturateInsteadOfOverflowing() {
        let late = PeerInstant(nanoseconds: .max - 1)
        #expect(late.advanced(by: .seconds(10)) == PeerInstant(nanoseconds: .max))
        #expect(PeerInstant(nanoseconds: .min).since(late) == .nanoseconds(Int64.min))
        #expect(Duration.seconds(1).wholeNanoseconds == 1_000_000_000)
        #expect(Duration.milliseconds(1_234).millisecondsText == "1234.0 ms")
    }
}
