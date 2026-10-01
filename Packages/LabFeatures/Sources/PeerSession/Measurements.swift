import Foundation

/// How another device's monotonic clock relates to this one's.
///
/// Two monotonic clocks cannot be compared directly. Each round trip of a clock probe gives an
/// offset and a delay; the estimate keeps the round trip with the smallest delay among recent
/// ones, whose offset is the most certain. The true offset lies within `uncertainty` of `offset`
/// if the two directions of that round trip took equal time, which is an assumption, not a
/// measurement. A new epoch or a new link discards the estimate.
public struct ClockEstimate: Hashable, Sendable {
    /// The other clock minus this one.
    public let offset: Duration
    /// Half the best round trip's network delay.
    public let uncertainty: Duration
    /// The best round trip's delay.
    public let roundTrip: Duration
    /// When, on this device's clock, the best round trip completed.
    public let calibratedAt: PeerInstant
    /// Round trips in the window the estimate chose from.
    public let sampleCount: Int

    /// How long ago the estimate was calibrated.
    public func age(at now: PeerInstant) -> Duration { now.since(calibratedAt) }

    /// Converts a reading of the other clock to this device's clock.
    public func localInstant(forRemote remote: PeerInstant) -> PeerInstant {
        remote.advanced(by: .zero - offset)
    }
}

/// Collects clock probe round trips and keeps the best recent one.
public struct ClockEstimator: Sendable {
    public static let window = 8

    private struct RoundTrip {
        let offset: Duration
        let delay: Duration
        let completedAt: PeerInstant
    }

    private var roundTrips: [RoundTrip] = []
    /// Round trips refused because their times were inconsistent (a negative delay).
    public private(set) var rejected = 0

    public init() {}

    /// Adds one round trip: `t0` and `t3` on this clock, `t1` and `t2` on the other.
    public mutating func add(sent t0: PeerInstant, received t1: PeerInstant, answered t2: PeerInstant, returned t3: PeerInstant) {
        let delay = t3.since(t0) - t2.since(t1)
        guard delay >= .zero, t2 >= t1, t3 >= t0 else {
            rejected += 1
            return
        }
        let offset = (t1.since(t0) + t2.since(t3)) / 2
        roundTrips.append(RoundTrip(offset: offset, delay: delay, completedAt: t3))
        if roundTrips.count > Self.window { roundTrips.removeFirst(roundTrips.count - Self.window) }
    }

    public var estimate: ClockEstimate? {
        guard let best = roundTrips.min(by: { $0.delay < $1.delay }) else { return nil }
        return ClockEstimate(
            offset: best.offset, uncertainty: best.delay / 2, roundTrip: best.delay,
            calibratedAt: best.completedAt, sampleCount: roundTrips.count
        )
    }

    public mutating func reset() {
        roundTrips.removeAll()
    }
}

/// Watches one sender's sequence numbers on one channel.
public struct SequenceTracker: Hashable, Sendable {
    public enum Observation: Hashable, Sendable {
        case inOrder
        /// Some numbers were skipped: those envelopes never arrived.
        case gap(missing: UInt64)
        /// Not newer than the last one: a duplicate, or overtaken by a newer envelope.
        case stale
    }

    public private(set) var last: UInt64 = 0
    public private(set) var gaps = 0
    public private(set) var missing: UInt64 = 0
    public private(set) var stale = 0

    public init() {}

    public mutating func observe(_ sequence: UInt64) -> Observation {
        guard sequence > last else {
            stale += 1
            return .stale
        }
        defer { last = sequence }
        if sequence == last + 1 { return .inOrder }
        let skipped = sequence - last - 1
        gaps += 1
        missing += skipped
        return .gap(missing: skipped)
    }
}

/// Whether a peer is being heard.
public enum Presence: Hashable, Sendable {
    /// Heard recently.
    case live
    /// Connected, but not heard for longer than the session's stale threshold. What it last sent
    /// may no longer be true.
    case stale(since: PeerInstant)
    /// The link closed, or silence lasted past the disconnect threshold.
    case disconnected(since: PeerInstant)

    public var title: String {
        switch self {
        case .live: "Live"
        case .stale: "Stale"
        case .disconnected: "Disconnected"
        }
    }

    public var isLive: Bool { self == .live }
}

/// The time limits one session uses. Design targets for a local network, not measurements.
public struct SessionTiming: Hashable, Sendable {
    /// How often each side probes the other's clock, which doubles as a heartbeat.
    public var probeInterval: Duration
    /// Silence after which a peer is shown as stale.
    public var staleAfter: Duration
    /// Silence after which the link is closed and the peer shown as disconnected.
    public var disconnectAfter: Duration
    /// The oldest a command may be when admitted, measured with the clock estimate.
    public var commandLifetime: Duration
    /// How long a command waits for its result before it is sent again under the same ID.
    public var resendAfter: Duration
    /// How long a sensitive command may wait for a person at the conductor.
    public var approvalLifetime: Duration

    public init(
        probeInterval: Duration = .milliseconds(500),
        staleAfter: Duration = .seconds(2),
        disconnectAfter: Duration = .seconds(8),
        commandLifetime: Duration = .seconds(5),
        resendAfter: Duration = .seconds(1),
        approvalLifetime: Duration = .seconds(30)
    ) {
        self.probeInterval = probeInterval
        self.staleAfter = staleAfter
        self.disconnectAfter = disconnectAfter
        self.commandLifetime = commandLifetime
        self.resendAfter = resendAfter
        self.approvalLifetime = approvalLifetime
    }

    public static let standard = SessionTiming()

    func presence(lastHeard: PeerInstant, now: PeerInstant) -> Presence {
        let silence = now.since(lastHeard)
        if silence > disconnectAfter { return .disconnected(since: lastHeard.advanced(by: disconnectAfter)) }
        if silence > staleAfter { return .stale(since: lastHeard.advanced(by: staleAfter)) }
        return .live
    }
}
