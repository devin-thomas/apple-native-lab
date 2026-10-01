import LabSupport
import LocalConstellation
import Observation
import PeerSession
import PeerSessionNetwork

/// Local Constellation on the Apple TV (LAB-019): the television is the display.
///
/// Live, it finds a conductor on the local network and joins as the display, after staging the
/// local network permission (CORE-004). The fallback is the whole simulation on this Apple TV.
/// This host has no lab store, so the simulation's show is stored in memory for this launch only,
/// through an operation service with the same grant policy as the Mac and iPhone.
@MainActor
@Observable
final class TVConstellationModel {
    private(set) var simulation: ConstellationSimulation?
    private(set) var joiner: LiveJoiner?
    private(set) var staging: String?
    private(set) var problem: String?
    private let identity: LocalIdentity
    private let trust = InMemoryTrustStore()

    init() {
        let draft = LocalIdentity(name: "Native Lab")
        identity = LocalIdentity(name: "Native Lab on Apple TV \(draft.id.shortForm.prefix(4))")
    }

    func startSimulation() async {
        guard simulation == nil else { return }
        do {
            let simulation = ConstellationSimulation(
                backend: ServiceShowBackend.inMemory(), storeDescription: "memory on this Apple TV, for this launch only",
                sheet: try CueSheet.bundled()
            )
            self.simulation = simulation
            await simulation.start()
        } catch {
            problem = "The bundled cue sheet did not load, so the show cannot start."
        }
    }

    /// Browses for a conductor to join as the display. Nothing is browsed before this.
    func joinAsDisplay() async {
        guard joiner == nil else { return }
        let action = FeatureAction(capability: .localNetwork, experimentID: LocalConstellation.experimentID, title: "Join a live show as the display")
        switch await PermissionStager.live().request(for: action) {
        case .granted, .notRequired:
            staging = nil
        case .systemAsksOnUse(let route):
            staging = "The system may ask to allow local network access now. If access is declined: \(route.summary)"
        case .fallback(let route, _):
            staging = "Local network access is not available. \(route.summary)"
            return
        }
        let joiner = LiveJoiner(role: .display, identity: identity, trust: trust, network: LANNetwork(serviceType: LocalConstellation.serviceType))
        self.joiner = joiner
        await joiner.startBrowsing()
    }

    func stopJoining() async {
        await joiner?.shutdown()
        joiner = nil
    }
}
