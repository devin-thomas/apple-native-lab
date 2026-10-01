import LabDomain
import PointInspect

/// Point, Inspect, Propose's way into the host (LAB-012).
///
/// Reads and proposals go through `LabDataService` as `PointInspect.proposer`. Creating the
/// Inspections collection and committing the item go through `LabLibrary.submit` as a user
/// action, so they run as the app UI and their receipts join the session list.
struct LibraryPointInspectBackend: PointInspectBackend {
    let library: LabLibrary

    func collection(_ id: CollectionID) async throws(InspectFailure) -> LabCollection? {
        let service = try await opened()
        do {
            return try await service.collection(id, as: PointInspect.proposer)
        } catch .notFound {
            return nil
        } catch {
            throw .refused(error)
        }
    }

    func propose(_ operation: DomainOperation) async throws(InspectFailure) -> OperationProposal {
        let service = try await opened()
        do {
            return try await service.propose(operation, as: PointInspect.proposer)
        } catch {
            throw .refused(error)
        }
    }

    func createCollection(_ draft: CollectionDraft, requestID: RequestID) async throws(InspectFailure) -> ActionReceipt {
        try await submit(.createCollection(draft: draft), requestID: requestID)
    }

    func commit(_ inspection: ApprovedInspection) async throws(InspectFailure) -> ActionReceipt {
        try await submit(inspection.operation, requestID: inspection.requestID)
    }

    private func submit(_ operation: DomainOperation, requestID: RequestID) async throws(InspectFailure) -> ActionReceipt {
        do {
            return try await library.submit(operation, requestID: requestID, authority: .userAction, names: [:]).receipt
        } catch {
            throw InspectFailure(error)
        }
    }

    private func opened() async throws(InspectFailure) -> LabDataService {
        do { return try await library.openedService() } catch { throw InspectFailure(error) }
    }
}

extension InspectFailure {
    init(_ failure: LabLibrary.SubmitFailure) {
        switch failure {
        case .unavailable(let reason): self = .unavailable(reason)
        case .refused(let error): self = .refused(error)
        }
    }
}
