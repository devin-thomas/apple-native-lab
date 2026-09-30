import LabDomain
import LocalConstellation
import Observation
import PeerSession

/// LAB-019 Local Constellation in this host: the single-device simulation over the lab's own
/// store, and, in a Companions build, the live path on the local network.
@MainActor
@Observable
final class ConstellationModel {
    static let shared = ConstellationModel()

    private(set) var simulation: ConstellationSimulation?
    private(set) var problem: String?
    #if LAB_PROFILE_COMPANIONS
    let live = LiveConstellation()
    #endif

    /// The simulation, started on first use. Its show commits through this library's operation
    /// service, so its receipts appear with every other receipt.
    func simulation(for library: LabLibrary) async -> ConstellationSimulation? {
        if let simulation { return simulation }
        let sheet: CueSheet
        do {
            sheet = try CueSheet.bundled()
        } catch {
            problem = "The bundled cue sheet did not load, so the show cannot start."
            return nil
        }
        let simulation = ConstellationSimulation(
            backend: LibraryShowBackend(library: library), storeDescription: "this Mac or device's lab store", sheet: sheet
        )
        self.simulation = simulation
        await simulation.start()
        return simulation
    }

    /// Brings the show in line with the store after a receipt from anywhere, such as Reset Demo
    /// pausing it or an undo in the receipt inspector.
    func storeChanged() async {
        await simulation?.syncFromStore()
        #if LAB_PROFILE_COMPANIONS
        await live.conductor?.syncFromStore()
        #endif
    }
}

/// The show's stored session through this host's library and `LabDataService`: reads as the app
/// UI, and commits as the app UI for the person here or as the authorized peer, with a grant for
/// that change alone, when the person here allowed a peer's request.
struct LibraryShowBackend: ShowSessionBackend {
    let library: LabLibrary

    func showSession() async throws(ShowBackendError) -> LabSession? {
        let service: LabDataService
        do { service = try await library.openedService() } catch { throw ShowBackendError(error) }
        do { return try await service.session(LocalConstellation.showSessionID, as: LabDataService.appUI) } catch { throw .refused(error) }
    }

    func commit(_ operation: DomainOperation, requestID: RequestID, authority: ShowAuthority) async throws(ShowBackendError) -> ActionReceipt {
        let commitAuthority: CommitAuthority = switch authority {
        case .conductorPerson: .userAction
        case .allowedPeer(let approval): .peerApproved(approval)
        }
        do {
            return try await library.submit(
                operation, requestID: requestID, authority: commitAuthority,
                names: [.session(LocalConstellation.showSessionID): LocalConstellation.showSessionName]
            ).receipt
        } catch {
            throw ShowBackendError(error)
        }
    }
}

extension ShowBackendError {
    init(_ failure: LabLibrary.SubmitFailure) {
        switch failure {
        case .unavailable(let reason): self = .unavailable(reason)
        case .refused(let error): self = .refused(error)
        }
    }
}
