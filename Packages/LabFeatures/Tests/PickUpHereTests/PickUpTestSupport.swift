import Foundation
import LabDomain
import PickUpHere
import Synchronization

/// One lab for a test: an in-memory store, the host's grant policy, and one collection of the
/// person's own. Reads and commits go through `OperationService`.
struct PickUpLab {
    let store = InMemoryOperationStore()
    let service: OperationService
    let actor = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    let collection: CollectionID
    let backend: ServicePickUpBackend

    static func make(revoked: @escaping @Sendable (ItemID) -> Bool = { _ in false }) async throws -> PickUpLab {
        try await PickUpLab(revoked: revoked)
    }

    private init(revoked: @escaping @Sendable (ItemID) -> Bool) async throws {
        let ledger = GrantLedger()
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
        collection = CollectionID()
        backend = ServicePickUpBackend(service: service, actor: actor, revoked: revoked)
        let draft = CollectionDraft(id: collection, title: try EntityTitle("Drafts"))
        _ = try await service.perform(
            OperationRequest(id: RequestID(), operation: .createCollection(draft: draft), actor: actor)
        )
    }

    @discardableResult
    func addItem(id: ItemID = ItemID(), title: String, note: String) async throws -> LabItem {
        let draft = ItemDraft(
            id: id,
            in: collection,
            title: try EntityTitle(title),
            note: try ItemNote(note)
        )
        _ = try await service.perform(
            OperationRequest(id: RequestID(), operation: .createItem(draft: draft), actor: actor)
        )
        return try await service.findItem(id, as: actor)
    }

    func itemCount() async -> Int {
        await store.items(in: nil).count
    }
}

/// A backend whose access check waits, so a test can cancel it, and that records whether the item
/// was read.
final class GateBackend: PickUpBackend, Sendable {
    let access: DraftAccess
    private let reads = Mutex(0)

    init(access: DraftAccess) { self.access = access }

    var itemReads: Int { reads.withLock { $0 } }

    func access(to id: ItemID) async throws(PickUpError) -> DraftAccess {
        do { try await Task.sleep(for: .seconds(30)) } catch { throw .cancelled }
        return access
    }

    func item(_ id: ItemID) async throws(PickUpError) -> LabItem? {
        reads.withLock { $0 += 1 }
        return nil
    }

    func items() async throws(PickUpError) -> [LabItem] { [] }

    func collections() async throws(PickUpError) -> [LabCollection] { [] }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(PickUpError) -> ActionReceipt {
        throw .unavailable
    }
}

enum Sentinel {
    static let text = "SENTINEL-SECTION-TEXT"
    static let note = "Opening\n\n\(text)\n\nClosing check"
}
