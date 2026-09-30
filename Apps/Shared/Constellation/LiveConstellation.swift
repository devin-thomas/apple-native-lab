#if LAB_PROFILE_COMPANIONS
import LabSupport
import LocalConstellation
import Observation
import PeerSession
import PeerSessionNetwork

/// The live path, in a Companions build only: this device hosts the show as the conductor, or
/// joins one as a controller or display, on the local network.
///
/// Nothing touches the network until a person chooses Host or Join. Each first stages the local
/// network permission through `PermissionStager` (CORE-004): the lab cannot read that permission
/// in advance, so the system may ask when the adapter starts, and a denial arrives as the
/// adapter's status. The simulation stays available throughout.
@MainActor
@Observable
final class LiveConstellation {
    private(set) var conductor: LiveConductor?
    private(set) var joiner: LiveJoiner?
    /// What staging the permission found, for people.
    private(set) var staging: String?
    /// This launch's identity. Pairings last until the app quits.
    let identity: LocalIdentity
    private let trust = InMemoryTrustStore()
    private let network = LANNetwork(serviceType: LocalConstellation.serviceType)

    init() {
        #if os(macOS)
        let device = "Mac"
        #elseif os(tvOS)
        let device = "Apple TV"
        #else
        let device = "iPhone"
        #endif
        // A neutral name: advertising the device's own name could reveal a person's name.
        let draft = LocalIdentity(name: "Native Lab")
        identity = LocalIdentity(name: "Native Lab on \(device) \(draft.id.shortForm.prefix(4))")
    }

    /// Hosts the show on the local network, after staging the permission.
    func host(library: LabLibrary) async {
        guard conductor == nil, await stage("Host a live show") else { return }
        let sheet: CueSheet
        do { sheet = try CueSheet.bundled() } catch {
            staging = "The bundled cue sheet did not load."
            return
        }
        let conductor = LiveConductor(identity: identity, trust: trust, network: network, backend: LibraryShowBackend(library: library), sheet: sheet)
        self.conductor = conductor
        await conductor.start()
    }

    /// Browses for a conductor to join as `role`, after staging the permission.
    func join(as role: PeerRole) async {
        guard joiner == nil, await stage(role == .display ? "Join a live show as a display" : "Join a live show as a controller") else { return }
        let joiner = LiveJoiner(role: role, identity: identity, trust: trust, network: network)
        self.joiner = joiner
        await joiner.startBrowsing()
    }

    func stopHosting() async {
        await conductor?.stop()
        conductor = nil
    }

    func stopJoining() async {
        await joiner?.shutdown()
        joiner = nil
    }

    private func stage(_ title: String) async -> Bool {
        let action = FeatureAction(capability: .localNetwork, experimentID: LocalConstellation.experimentID, title: title)
        switch await PermissionStager.live().request(for: action) {
        case .granted, .notRequired:
            staging = nil
            return true
        case .systemAsksOnUse(let route):
            staging = "The system may ask to allow local network access now. If access is declined: \(route.summary)"
            return true
        case .fallback(let route, let reason):
            staging = "\(Self.explain(reason)) \(route.summary)"
            return false
        }
    }

    private static func explain(_ reason: FallbackReason) -> String {
        switch reason {
        case .denied, .declinedNow: "Local network access was declined."
        case .restricted: "Local network access is restricted on this device."
        case .missingPurposeString(let key): "This build does not declare \(key), so it cannot ask."
        case .missingEntitlement(let key): "This build is not signed with \(key), so the sandbox blocks the network."
        case .unknownStatus: "The local network permission could not be read."
        }
    }
}
#endif
