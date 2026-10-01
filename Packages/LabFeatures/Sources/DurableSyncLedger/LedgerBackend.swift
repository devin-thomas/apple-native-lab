import CryptoKit
import Foundation
import LabDomain

enum RequestIdentity {
    /// A stable request ID for a follow-up step of one mutation, such as restoring before an update.
    static func step(_ mutation: MutationID, _ name: String) -> RequestID {
        RequestID(rawValue: uuid(named: mutation.rawValue.uuidString + "\n" + name))
    }

    static func uuid(named name: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(name.utf8)))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }
}

/// How destructive commits meet ADR-013.
public enum LedgerGrantMode: Sendable {
    /// The host is inside a person's action. A destructive commit gets a 30-second grant for that
    /// operation, and the grant is revoked when the commit returns. A model tool still cannot
    /// commit: issuing the grant is refused by the adapter ceiling.
    case issueForUserAction
    /// Nothing is issued. The operation service's own check is the refusal.
    case requireExisting
}

/// The ledger's only way into the lab. Materializing an edit is one `OperationService` commit.
public protocol LedgerBackend: Sendable {
    func collection(_ id: CollectionID) async throws(LedgerError) -> LabCollection?
    func item(_ id: ItemID) async throws(LedgerError) -> LabItem?
    func perform(_ operation: DomainOperation, id: RequestID) async throws(LedgerError) -> ActionReceipt
}

/// `OperationService` behind the ledger, with the host's grant ledger.
public struct ServiceBackend: LedgerBackend, Sendable {
    public let service: OperationService
    public let actor: ActorScope
    public let grants: GrantLedger
    public let grantMode: LedgerGrantMode

    public init(
        service: OperationService,
        actor: ActorScope,
        grants: GrantLedger,
        grantMode: LedgerGrantMode
    ) {
        self.service = service
        self.actor = actor
        self.grants = grants
        self.grantMode = grantMode
    }

    public func collection(_ id: CollectionID) async throws(LedgerError) -> LabCollection? {
        do {
            return try await service.findCollection(id, as: actor)
        } catch .notFound {
            return nil
        } catch {
            throw Self.map(error)
        }
    }

    public func item(_ id: ItemID) async throws(LedgerError) -> LabItem? {
        do {
            return try await service.findItem(id, as: actor)
        } catch .notFound {
            return nil
        } catch {
            throw Self.map(error)
        }
    }

    public func perform(_ operation: DomainOperation, id: RequestID) async throws(LedgerError) -> ActionReceipt {
        let request = OperationRequest(id: id, operation: operation, actor: actor)
        if operation.kind.isDestructive, grantMode == .issueForUserAction {
            let grant: CommitGrant
            do {
                grant = try grants.issue(for: operation, to: actor.adapter, lifetime: .seconds(30))
            } catch {
                throw .unauthorized
            }
            defer { grants.revoke(grant.id) }
            return try await commit(request)
        }
        return try await commit(request)
    }

    private func commit(_ request: OperationRequest) async throws(LedgerError) -> ActionReceipt {
        do {
            return try await service.perform(request)
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: OperationError) -> LedgerError {
        switch error {
        case .unauthorized: .unauthorized
        case .storeFailure: .storage
        case .invalidPayload(let reason): .invalidMutation(LedgerError.describe(reason))
        case .notFound: .domain("The record is not in the lab.")
        case .requestIDReused: .domain("That request was already used for a different edit.")
        case .ruleViolation: .domain("The lab refused the edit.")
        }
    }
}
