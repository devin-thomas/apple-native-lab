import Synchronization

/// What a recorded interval was measured against. Every run states its timebase, and an export
/// carries the declaration with every number.
public enum Timebase: String, Hashable, Sendable, Codable, CaseIterable {
    /// Swift `ContinuousClock`: monotonic, unaffected by wall-clock changes, and still counting
    /// while the device sleeps.
    case continuous = "swift-continuous-clock"
    /// Swift `SuspendingClock`: monotonic and unaffected by wall-clock changes, but paused while
    /// the device sleeps.
    case suspending = "swift-suspending-clock"
    /// A clock a test or preview advances by hand. Its intervals are scripted, not measured.
    case manual = "manual-test-clock"

    /// Whether intervals on this timebase measure elapsed real time. Only those can support a
    /// performance claim.
    public var measuresRealTime: Bool {
        switch self {
        case .continuous, .suspending: true
        case .manual: false
        }
    }

    /// The declaration written beside every interval.
    public var declaration: String {
        switch self {
        case .continuous:
            "Swift ContinuousClock on the machine that ran the replay: monotonic, not affected by wall-clock changes, counts time asleep. Intervals are nanoseconds from the run's first reading and are comparable only within one run."
        case .suspending:
            "Swift SuspendingClock on the machine that ran the replay: monotonic, not affected by wall-clock changes, paused while asleep. Intervals are nanoseconds from the run's first reading and are comparable only within one run."
        case .manual:
            "A manual test clock advanced by the caller. Its intervals are scripted values, not measurements of real time, and support no performance claim."
        }
    }
}

/// A monotonic source of elapsed time, injected into the demo runner.
///
/// `now()` returns the time since the clock's own fixed origin. Only differences between two
/// readings of the same clock mean anything.
public protocol IntervalClock: Sendable {
    var timebase: Timebase { get }
    func now() -> Duration
}

/// Elapsed time on Swift's `ContinuousClock`. The default for real runs.
public struct ContinuousIntervalClock: IntervalClock {
    private let origin: ContinuousClock.Instant

    public init() { origin = ContinuousClock.now }

    public var timebase: Timebase { .continuous }

    public func now() -> Duration { ContinuousClock.now - origin }
}

/// Elapsed time on Swift's `SuspendingClock`, for runs that should not count time asleep.
public struct SuspendingIntervalClock: IntervalClock {
    private let origin: SuspendingClock.Instant

    public init() { origin = SuspendingClock.now }

    public var timebase: Timebase { .suspending }

    public func now() -> Duration { SuspendingClock.now - origin }
}

/// A clock that moves only when told to, for tests and previews. Its timebase is `manual`, so
/// nothing it produces can become a performance claim.
public final class ManualIntervalClock: IntervalClock {
    private let state: Mutex<(elapsed: Duration, stepPerReading: Duration)>

    /// - Parameter stepPerReading: How far the clock advances after each reading, so a run with
    ///   no explicit `advance(by:)` still records distinct, predictable intervals.
    public init(stepPerReading: Duration = .zero) {
        state = Mutex((.zero, stepPerReading))
    }

    public var timebase: Timebase { .manual }

    public func now() -> Duration {
        state.withLock { state in
            let reading = state.elapsed
            state.elapsed += state.stepPerReading
            return reading
        }
    }

    public func advance(by duration: Duration) {
        state.withLock { $0.elapsed += duration }
    }
}
