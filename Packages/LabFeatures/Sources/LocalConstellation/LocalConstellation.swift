import Foundation
import LabDomain
import PeerSession

/// LAB-019 Local Constellation: a conductor, a controller, and a display on a local network, or
/// all three on one device over the loopback with identical wire messages.
///
/// The session layer is `PeerSession`; this module adds the show: its cue sheet, its commands and
/// pointer samples, its rules, and the one sensitive request, starting or pausing the show, which
/// a peer may only ask for. The person at the conductor allows it, and the host commits it through
/// its `OperationService` as an authorized peer with a grant for exactly that change (ADR-011,
/// ADR-013).
public enum LocalConstellation {
    public static let experimentID = "LAB-019"
    public static let title = "Local Constellation"
    public static let symbol = "point.3.connected.trianglepath.dotted"

    /// The Bonjour type a live conductor advertises. Hosts that browse or advertise list it in
    /// `NSBonjourServices`.
    public static let serviceType = "_nativelab-lc._tcp"

    /// The stored running-or-paused flag behind "the show is running". A demo-namespace
    /// `LabSession`, so Reset Demo pauses it; fixed, so every device and launch names the same one.
    public static let showSessionID = SessionID(rawValue: UUID(uuidString: "4C0C0019-5E55-4E1A-9C0B-0000000000C1")!)

    /// A name for the show's session in receipts.
    public static let showSessionName = "Constellation show"
}
