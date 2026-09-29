import Foundation
import LabDomain
import LabStore

/// Why the host is committing a change. A commit grant (ADR-013) is issued only for these reasons.
enum CommitAuthority: Sendable {
    /// A person pressed a control or confirmed a dialog for this exact change.
    case userAction
    /// First run: the host seeds an empty demo namespace. The service checks the namespace is
    /// still empty before issuing the grant, so this path can never remove anything.
    case firstRunSeed
}

/// The host's app-UI adapter: the only host code that holds the store or the operation service.
///
/// Every change goes through `OperationService` under the app-UI actor, so it is authorized,
/// idempotent per request ID, and recorded with its receipt (ADR-011). Destructive changes also
/// need a short-lived grant (ADR-013): this adapter issues one for exactly the operation being
/// committed, only for a `CommitAuthority`, and revokes it as soon as the commit returns. Views
/// never see this type; they talk to `LabLibrary`, which calls it.
///
/// Reads of demo content go through the service too. The one direct store read is the namespace
/// census, because the service has no read that lists or counts collections; it returns counts
/// only, so the user namespace is never read for anything but its size.
struct LabDataService: Sendable {
    /// App UI may read, propose, commit, and commit destructive changes such as Reset Demo.
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    private let store: SQLiteOperationStore
    private let service: OperationService
    private let grants: GrantLedger

    private init(store: SQLiteOperationStore) {
        self.store = store
        let grants = GrantLedger()
        self.grants = grants
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: grants))
    }

    /// Opens the store at `url`, creating or migrating the file as needed.
    static func open(at url: URL) async throws(StoreError) -> LabDataService {
        LabDataService(store: try await SQLiteOperationStore(url: url))
    }

    /// Commits one request. A retry of the same intent passes the same request ID and gets the
    /// original receipt back instead of a second change.
    ///
    /// When the operation needs a grant, one is issued for this operation alone and revoked when
    /// the commit returns. If it cannot be issued, the policy refuses the commit: the path fails
    /// closed rather than open.
    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        authority: CommitAuthority
    ) async throws(OperationError) -> ActionReceipt {
        var grant: GrantID?
        if GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: Self.appUI.adapter),
           await mayGrant(operation, for: authority) {
            grant = try? grants.issue(for: operation, to: Self.appUI.adapter, lifetime: .seconds(30)).id
        }
        defer { if let grant { grants.revoke(grant) } }
        return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: Self.appUI))
    }

    private func mayGrant(_ operation: DomainOperation, for authority: CommitAuthority) async -> Bool {
        switch authority {
        case .userAction:
            return true
        case .firstRunSeed:
            guard case .resetDemo = operation, let census = try? await census() else { return false }
            return census.demo == NamespaceCount(collections: 0, items: 0, archived: 0)
        }
    }

    /// The seed's collections as stored, each with its items ordered by title. A collection the
    /// store does not have yet is left out, and so is anything outside the demo namespace.
    func demoContents(of seed: DemoSeed) async throws(OperationError) -> [DemoCollection] {
        var contents: [DemoCollection] = []
        for draft in seed.collections {
            let collection: LabCollection
            do {
                collection = try await service.findCollection(draft.id, as: Self.appUI)
            } catch .notFound {
                continue
            }
            guard collection.namespace == .demo else { continue }
            let filter: ItemFilter
            do {
                filter = try ItemFilter(collectionID: collection.id, includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
            } catch {
                throw .invalidPayload(error)
            }
            let items = try await service.findItems(filter, as: Self.appUI)
            contents.append(DemoCollection(collection: collection, items: items.filter { $0.namespace == .demo }))
        }
        return contents
    }

    /// How many collections and items each namespace holds. Counts only.
    func census() async throws(StoreError) -> NamespaceCensus {
        let collections = try await store.collections()
        let items = try await store.items(in: nil)
        func count(_ namespace: DataNamespace) -> NamespaceCount {
            let ownCollections = collections.filter { $0.namespace == namespace }
            let ownItems = items.filter { $0.namespace == namespace }
            return NamespaceCount(
                collections: ownCollections.count,
                items: ownItems.count,
                archived: ownCollections.count(where: \.isArchived) + ownItems.count(where: \.isArchived)
            )
        }
        return NamespaceCensus(demo: count(.demo), user: count(.user))
    }
}

/// One demo collection as stored, with its items.
struct DemoCollection: Identifiable, Hashable, Sendable {
    let collection: LabCollection
    let items: [LabItem]

    var id: CollectionID { collection.id }
}

/// How much each namespace holds, for Settings and the collection browser.
struct NamespaceCensus: Hashable, Sendable {
    let demo: NamespaceCount
    let user: NamespaceCount
}

struct NamespaceCount: Hashable, Sendable {
    let collections: Int
    let items: Int
    /// Archived collections and items together. They are still stored and counted above.
    let archived: Int
}
