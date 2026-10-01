import Foundation
import LabDomain
import Testing
@testable import CommerceWithoutTricks

struct ServiceBackend: CommerceBackend {
    let service: OperationService
    var actor = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    func item(_ id: ItemID) async throws(CommerceError) -> LabItem? {
        do { return try await service.findItem(id, as: actor) } catch {
            if case .notFound = error { return nil }
            throw .operation(error)
        }
    }

    func collection(_ id: CollectionID) async throws(CommerceError) -> LabCollection? {
        do { return try await service.findCollection(id, as: actor) } catch {
            if case .notFound = error { return nil }
            throw .operation(error)
        }
    }

    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(CommerceError) -> ActionReceipt {
        _ = names
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw .operation(error)
        }
    }
}

struct CancelledBackend: CommerceBackend {
    func item(_ id: ItemID) async throws(CommerceError) -> LabItem? { nil }
    func collection(_ id: CollectionID) async throws(CommerceError) -> LabCollection? { nil }
    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(CommerceError) -> ActionReceipt {
        throw .cancelled
    }
}

struct UnavailableBackend: CommerceBackend {
    func item(_ id: ItemID) async throws(CommerceError) -> LabItem? {
        throw .labUnavailable("The store did not open.")
    }
    func collection(_ id: CollectionID) async throws(CommerceError) -> LabCollection? {
        throw .labUnavailable("The store did not open.")
    }
    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(CommerceError) -> ActionReceipt {
        throw .labUnavailable("The store did not open.")
    }
}

@MainActor
func commerceLab() -> (CommerceDesk, ServiceBackend) {
    let desk = CommerceDesk(simulator: TransactionStateSimulator(sessionID: UUID(uuidString: "04004004-1040-4040-8040-040040040040")!))
    let backend = ServiceBackend(service: OperationService(store: InMemoryOperationStore(), policy: GrantAuthorizationPolicy(ledger: GrantLedger())))
    return (desk, backend)
}

