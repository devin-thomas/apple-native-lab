/// Watches tracking for a relocalization that does not finish, and says when to offer recovery.
///
/// After an interruption, or when a saved table map is loaded, ARKit tries to find the known
/// surface again and reports `limited(.relocalizing)` meanwhile. That can take a while, or never
/// finish if the person moved to another room. The watch lets precision interactions stay
/// suspended while it runs, and after `patience` offers the two recoveries: keep looking, or start
/// fresh and place the table again. Starting fresh keeps every object's place on the table; only
/// the table's position in the room is found again.
public struct RelocalizationWatch: Sendable {
    public enum Advice: Hashable, Sendable {
        /// Nothing to recover from.
        case none
        /// Relocalizing for this long so far. Keep looking at the table.
        case searching(elapsed: Duration)
        /// Relocalizing for longer than `patience`. Offer Keep Looking and Start Fresh.
        case stalled(elapsed: Duration)
        /// Tracking came back while this watch was waiting.
        case recovered
    }

    public static let defaultPatience: Duration = .seconds(20)

    public let patience: Duration
    private var searchingSince: ContinuousClock.Instant?

    public init(patience: Duration = RelocalizationWatch.defaultPatience) {
        self.patience = patience
    }

    public var isSearching: Bool { searchingSince != nil }

    /// Feeds one tracking update, at `now`, and returns the advice for it.
    public mutating func observe(_ status: TrackingStatus, at now: ContinuousClock.Instant) -> Advice {
        let relocalizing = status == .limited(.relocalizing) || status == .interrupted
        guard relocalizing else {
            defer { searchingSince = nil }
            return searchingSince == nil || status != .normal ? .none : .recovered
        }
        let since = searchingSince ?? now
        searchingSince = since
        let elapsed = since.duration(to: now)
        return elapsed >= patience ? .stalled(elapsed: elapsed) : .searching(elapsed: elapsed)
    }

    /// Keep Looking: wait another full `patience` before offering recovery again.
    public mutating func keepLooking(at now: ContinuousClock.Instant) {
        if searchingSince != nil { searchingSince = now }
    }

    /// Start Fresh, or the session ended: forget the search.
    public mutating func reset() {
        searchingSince = nil
    }
}

/// A recorded tracking sequence, played into the same gate the live adapter feeds.
///
/// It proves the tabletop's contract without a camera: precision interactions suspend while
/// tracking is limited, the relocalization watch offers recovery, and everything comes back when
/// tracking does. Wherever it runs, it is labeled a replay: it is not evidence of ARKit, a camera,
/// or a real surface.
public struct TrackingReplay: Hashable, Sendable {
    public struct Step: Hashable, Sendable {
        public let status: TrackingStatus
        public let duration: Duration

        public init(_ status: TrackingStatus, for duration: Duration) {
            self.status = status
            self.duration = duration
        }
    }

    public let title: String
    public let steps: [Step]

    public init(title: String, steps: [Step]) {
        self.title = title
        self.steps = steps
    }

    /// A short session: it starts, tracks normally, loses tracking to fast motion, is
    /// interrupted, searches for the table long enough to stall, and recovers.
    public static let standard = TrackingReplay(title: "Tracking loss and recovery", steps: [
        Step(.limited(.initializing), for: .seconds(2)),
        Step(.normal, for: .seconds(3)),
        Step(.limited(.excessiveMotion), for: .seconds(3)),
        Step(.interrupted, for: .seconds(2)),
        Step(.limited(.relocalizing), for: .seconds(4)),
        Step(.normal, for: .seconds(1)),
    ])

    public var totalDuration: Duration {
        steps.reduce(.zero) { $0 + $1.duration }
    }

    /// The patience a relocalization watch uses during this replay, short enough that the replay
    /// reaches the stalled advice before it recovers.
    public static let replayPatience: Duration = .seconds(3)
}
