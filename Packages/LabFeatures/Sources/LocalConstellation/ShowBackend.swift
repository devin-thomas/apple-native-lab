import CryptoKit
import Foundation
import LabDomain
import PeerSession

/// The person at the conductor allowed one peer's request. Only `ShowHost.allow` creates one,
/// when that person presses Allow; nothing a peer sends can. A host that receives one issues a
/// grant for exactly the operation it commits, to the authorized-peer adapter, and revokes it
/// when the commit returns (ADR-013).
public struct PeerApproval: Hashable, Sendable {
    public let peer: PeerID
    public let peerName: String
    public let commandID: MessageID

    init(peer: PeerIdentity, commandID: MessageID) {
        self.peer = peer.id
        peerName = peer.name
        self.commandID = commandID
    }

    /// The request ID for the commit: derived from the peer and its command, so a resend of the
    /// same command returns the original receipt, and in its own namespace, so a peer cannot pick
    /// an ID another entry point used.
    public var requestID: RequestID {
        let digest = SHA256.hash(data: Data("LAB-019 peer request|\(peer.rawValue)|\(commandID.rawValue.uuidString)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return RequestID(rawValue: uuid)
    }
}

/// Why a show change is committed.
public enum ShowAuthority: Hashable, Sendable {
    /// The person at the conductor pressed Start or Pause there: the app-UI adapter.
    case conductorPerson
    /// A peer asked, and the person at the conductor allowed it: the authorized-peer adapter,
    /// with a grant for this change alone.
    case allowedPeer(PeerApproval)

    /// The adapter this authority commits through (ADR-011).
    public var adapter: AdapterKind {
        switch self {
        case .conductorPerson: .appUI
        case .allowedPeer: .authorizedPeer
        }
    }
}

public enum ShowBackendError: Error, Hashable, Sendable {
    case unavailable(String)
    case refused(OperationError)

    public var message: String {
        switch self {
        case .unavailable(let reason): reason
        case .refused(.unauthorized): "That entry point may not change the show. Nothing changed."
        case .refused: "The show could not be changed. Nothing changed."
        }
    }
}

/// The show's way into the host's domain: the stored session and its one operation, through the
/// host's `OperationService`. A host implements it over its own store; `ServiceShowBackend`
/// implements it over any service, such as an in-memory one for a device without a store.
public protocol ShowSessionBackend: Sendable {
    func showSession() async throws(ShowBackendError) -> LabSession?
    func commit(_ operation: DomainOperation, requestID: RequestID, authority: ShowAuthority) async throws(ShowBackendError) -> ActionReceipt
}

/// A backend over an `OperationService` whose policy requires grants for sensitive commits.
///
/// An allowed peer's change gets a grant for exactly that operation, to the authorized-peer
/// adapter, for 30 seconds, revoked when the commit returns. Anything else a peer might reach for
/// has no grant and fails closed at the commit.
public struct ServiceShowBackend: ShowSessionBackend {
    public static let conductorActor = ActorScope(adapter: .appUI, grants: [.read, .propose, .commit])
    public static let peerActor = ActorScope(adapter: .authorizedPeer, grants: [.read, .propose, .commit])

    public let service: OperationService
    public let ledger: GrantLedger

    public init(service: OperationService, ledger: GrantLedger) {
        self.service = service
        self.ledger = ledger
    }

    /// A service over a new in-memory store, for a device without the lab's store (the Apple TV's
    /// simulation) and for tests. Its state ends with the process.
    public static func inMemory() -> ServiceShowBackend {
        let ledger = GrantLedger()
        let service = OperationService(store: InMemoryOperationStore(), policy: GrantAuthorizationPolicy(ledger: ledger))
        return ServiceShowBackend(service: service, ledger: ledger)
    }

    public func showSession() async throws(ShowBackendError) -> LabSession? {
        do { return try await service.findSession(LocalConstellation.showSessionID, as: Self.conductorActor) } catch { throw .refused(error) }
    }

    public func commit(_ operation: DomainOperation, requestID: RequestID, authority: ShowAuthority) async throws(ShowBackendError) -> ActionReceipt {
        let actor: ActorScope
        var grant: GrantID?
        switch authority {
        case .conductorPerson:
            actor = Self.conductorActor
        case .allowedPeer:
            actor = Self.peerActor
            grant = try? ledger.issue(for: operation, to: .authorizedPeer, lifetime: .seconds(30)).id
        }
        defer { if let grant { ledger.revoke(grant) } }
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw .refused(error)
        }
    }
}
