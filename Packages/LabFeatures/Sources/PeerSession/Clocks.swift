import Foundation
import Synchronization

/// A clock that moves only when told to, for deterministic tests and replays.
public final class ManualPeerClock: PeerClock {
    private let reading: Mutex<Int64>

    public init(start: PeerInstant = PeerInstant(nanoseconds: 0)) {
        reading = Mutex(start.rawValue)
    }

    public func now() -> PeerInstant { PeerInstant(nanoseconds: reading.withLock { $0 }) }

    public func advance(by duration: Duration) {
        reading.withLock { $0 = PeerInstant(nanoseconds: $0).advanced(by: duration).rawValue }
    }
}

/// Another device's clock, simulated on this one: a base clock read with an offset.
///
/// The single-device simulation gives each simulated device its own offset, so the clock estimate
/// has a real error to find. Changing the offset steps the clock, which a real monotonic clock
/// never does; tests use it to make a device's clock look wrong.
public final class OffsetPeerClock: PeerClock {
    private let base: any PeerClock
    private let offsetNanoseconds: Mutex<Int64>

    public init(base: any PeerClock, offset: Duration) {
        self.base = base
        offsetNanoseconds = Mutex(offset.wholeNanoseconds)
    }

    public var offset: Duration {
        get { .nanoseconds(offsetNanoseconds.withLock { $0 }) }
    }

    public func setOffset(_ offset: Duration) {
        offsetNanoseconds.withLock { $0 = offset.wholeNanoseconds }
    }

    public func now() -> PeerInstant {
        base.now().advanced(by: offset)
    }
}
