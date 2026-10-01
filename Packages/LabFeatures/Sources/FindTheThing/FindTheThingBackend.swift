import Foundation
import LabDomain

/// Archives a lab item through the host's operation service, under the actor who asked.
///
/// Find the Thing never holds the store. A record that is not a lab item is removed from the app
/// index without a store write. A record that is a lab item leaves the index only after this
/// archive is admitted, or when the item is already archived or already gone.
public protocol FindTheThingBackend: Sendable {
    func archiveItem(
        id: ItemID,
        expected: Revision,
        actor: ActorScope,
        requestID: RequestID
    ) async throws(FindTheThingError) -> ActionReceipt
}

/// Used when no store is connected. An archive fails and the caller leaves the index unchanged.
public struct UnavailableFindBackend: FindTheThingBackend {
    public let reason: String

    public init(reason: String = "Native Lab has not opened its store, so a lab record cannot be archived. It is still in the index.") {
        self.reason = reason
    }

    public func archiveItem(
        id: ItemID,
        expected: Revision,
        actor: ActorScope,
        requestID: RequestID
    ) async throws(FindTheThingError) -> ActionReceipt {
        throw .unavailable(reason: reason)
    }
}

/// Archives through `OperationService` with the same grant rule the host uses for a destructive commit.
public struct ServiceFindBackend: FindTheThingBackend {
    let service: OperationService
    let ledger: GrantLedger

    public init(service: OperationService, ledger: GrantLedger) {
        self.service = service
        self.ledger = ledger
    }

    public func archiveItem(
        id: ItemID,
        expected: Revision,
        actor: ActorScope,
        requestID: RequestID
    ) async throws(FindTheThingError) -> ActionReceipt {
        let operation = DomainOperation.archiveItem(id: id, expected: expected)
        let grantID = try issueGrant(for: operation, to: actor.adapter)
        defer { if let grantID { ledger.revoke(grantID) } }
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw FindTheThingError(error)
        }
    }

    private func issueGrant(for operation: DomainOperation, to adapter: AdapterKind) throws(FindTheThingError) -> GrantID? {
        guard GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: adapter) else { return nil }
        do {
            return try ledger.issue(for: operation, to: adapter, lifetime: .seconds(30)).id
        } catch {
            throw .unauthorized(adapter: adapter, required: .commitDestructive, reason: .notGranted)
        }
    }
}
