import AppIntents
import LabDomain
import Observation
import SurfaceDeck

/// Connects Surface Deck's App Intents and snapshot to this host's store (LAB-004).
enum SurfaceDeckHost {
    /// Registers the backend every Surface Deck intent uses, and keeps the snapshot current as
    /// receipts arrive from any entry point, including Reset Demo and a receipt's undo. Call once
    /// at launch, beside `ActionAtlasHost.connect`.
    @MainActor
    static func connect(_ library: LabLibrary, model: SurfaceDeckModel = .shared) {
        model.connect(library)
        AppDependencyManager.shared.add(dependency: SurfaceDeckLink(
            backend: LibrarySessionBackend(library: library, model: model),
            openDeck: { model.requestOpen() }
        ))
        Task { @MainActor in
            // Observations delivers the first value and then each change: the store opening, and
            // every new receipt. Nothing is read on a timer.
            for await _ in Observations({ ReceiptMarker(isReady: library.phase == .ready, newest: library.receipts.first?.id) }) {
                guard library.phase == .ready else { continue }
                await model.refresh()
            }
        }
    }

    private struct ReceiptMarker: Hashable, Sendable {
        let isReady: Bool
        let newest: OperationID?
    }
}

/// Surface Deck's way into the host: reads and commits go through `LabLibrary` and
/// `LabDataService` under the adapter the entry point names, and each settled request refreshes
/// the snapshot. It never holds the store.
struct LibrarySessionBackend: SessionBackend {
    let library: LabLibrary
    let model: SurfaceDeckModel

    func session(via entryPoint: SessionEntryPoint) async throws(SurfaceDeckError) -> LabSession? {
        let service: LabDataService
        do { service = try await library.openedService() } catch { throw SurfaceDeckError(error) }
        do { return try await service.session(SurfaceDeck.sessionID, as: Self.actor(entryPoint)) } catch { throw .refused(error) }
    }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        via entryPoint: SessionEntryPoint,
        surface: SessionSurface
    ) async throws(SurfaceDeckError) -> ActionReceipt {
        await model.willCommit(from: surface)
        // Starting or pausing is not destructive, so neither authority needs a grant (ADR-013).
        let authority: CommitAuthority = entryPoint == .appUI ? .userAction : .intent(nil)
        do {
            return try await library.submit(
                operation, requestID: requestID, authority: authority,
                names: [.session(SurfaceDeck.sessionID): SurfaceDeck.sessionName]
            ).receipt
        } catch {
            throw SurfaceDeckError(error)
        }
    }

    func didSettle(_ outcome: SessionOutcome, surface: SessionSurface) async {
        await model.settle(outcome, surface: surface)
    }

    static func actor(_ entryPoint: SessionEntryPoint) -> ActorScope {
        switch entryPoint {
        case .appUI: LabDataService.appUI
        case .appIntent: LabDataService.appIntent
        }
    }
}

extension SurfaceDeckError {
    init(_ failure: LabLibrary.SubmitFailure) {
        switch failure {
        case .unavailable(let reason): self = .unavailable(reason: reason)
        case .refused(let error): self = .refused(error)
        }
    }
}
