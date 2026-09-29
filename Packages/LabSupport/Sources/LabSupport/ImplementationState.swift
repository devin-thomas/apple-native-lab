/// The only implementation states the lab uses (SPEC §7).
///
/// A simulator or fixture run can establish `implemented` for a fallback. It never
/// establishes `deviceVerified` for a real hardware adapter.
public enum ImplementationState: String, Codable, Sendable, CaseIterable, Comparable {
    case specified
    case spiked
    case implemented
    case deviceVerified = "device-verified"
    case releaseReady = "release-ready"
    case blocked

    public var title: String {
        switch self {
        case .specified: "Specified"
        case .spiked: "Spiked"
        case .implemented: "Implemented"
        case .deviceVerified: "Device verified"
        case .releaseReady: "Release ready"
        case .blocked: "Blocked"
        }
    }

    /// Whether the state claims something runs, as opposed to being planned or stuck.
    public var isLive: Bool {
        switch self {
        case .implemented, .deviceVerified, .releaseReady: true
        case .specified, .spiked, .blocked: false
        }
    }

    private var rank: Int {
        switch self {
        case .blocked: 0
        case .specified: 1
        case .spiked: 2
        case .implemented: 3
        case .deviceVerified: 4
        case .releaseReady: 5
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}
