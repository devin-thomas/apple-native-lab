import ActionAtlas
import Foundation
import LabDomain
import LabStore
import LocalConstellation

/// Why the host is committing a change. A commit grant (ADR-013) is issued only for these reasons.
enum CommitAuthority: Sendable {
    /// A person pressed a control or confirmed a dialog for this exact change.
    case userAction
    /// First run: the host seeds an empty demo namespace. The service checks the namespace is
    /// still empty before issuing the grant, so this path can never remove anything.
    case firstRunSeed
    /// An App Intent the system ran (LAB-001). It holds a confirmation only when the person
    /// confirmed this exact change in the system's confirmation dialog, and that confirmation is
    /// the only way an intent's destructive change gets a grant.
    case intent(IntentConfirmation?)
    /// LAB-019 Local Constellation: a paired peer asked to start or pause the show, and the person
    /// at this conductor allowed that exact request. Only `ShowHost.allow` creates the approval.
    case peerApproved(PeerApproval)

    /// The adapter a commit arrives through, fixed by where its authority comes from (ADR-011).
    var actor: ActorScope {
        switch self {
        case .userAction, .firstRunSeed: LabDataService.appUI
        case .intent: LabDataService.appIntent
        case .peerApproved: LabDataService.authorizedPeer
        }
    }
}

/// The host's app-UI adapter: the only host code that holds the store or the operation service.
///
/// Every change goes through `OperationService` under the app-UI actor, so it is authorized,
/// idempotent per request ID, and recorded with its receipt (ADR-011). Destructive changes also
/// need a short-lived grant (ADR-013): this adapter issues one for exactly the operation being
/// committed, only for a `CommitAuthority`, and revokes it as soon as the commit returns. Views
/// never see this type; they talk to `LabLibrary`, which calls it.
///
/// App Intents (LAB-001 Action Atlas) take the same path under the App Intent actor: the
/// authority `.intent` selects that actor, and its grant comes only from the system's
/// confirmation of the exact change.
///
/// Reads of demo content go through the service too. The direct store reads are the namespace
/// census, which returns counts only, and the collection list, which takes identifiers only and
/// reads each collection through the service, because the service has no read that lists or
/// counts collections.
struct LabDataService: Sendable {
    /// App UI may read, propose, commit, and commit destructive changes such as Reset Demo.
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    /// App Intents have the same ceiling as the app UI (ADR-011); a destructive commit still needs
    /// a grant, which only the system's confirmation of that change provides (ADR-013).
    static let appIntent = ActorScope(adapter: .appIntent, grants: Set(Permission.allCases))
    /// A paired peer on a local session (LAB-019). Its ceiling excludes destructive commits, and
    /// every commit it makes needs a grant, which only the conductor's person allowing that exact
    /// request provides (ADR-011, ADR-013).
    static let authorizedPeer = ActorScope(adapter: .authorizedPeer, grants: [.read, .propose, .commit])

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
        let actor = authority.actor
        var grant: GrantID?
        if GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: actor.adapter),
           await mayGrant(operation, for: authority) {
            grant = try? grants.issue(for: operation, to: actor.adapter, lifetime: .seconds(30)).id
        }
        defer { if let grant { grants.revoke(grant) } }
        return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
    }

    private func mayGrant(_ operation: DomainOperation, for authority: CommitAuthority) async -> Bool {
        switch authority {
        case .userAction:
            return true
        case .firstRunSeed:
            guard case .resetDemo = operation, let census = try? await census() else { return false }
            return census.demo == NamespaceCount(collections: 0, items: 0, archived: 0)
        case .intent(let confirmation):
            return confirmation?.covers(operation) == true
        case .peerApproved:
            // The one change a peer can ask for: starting or pausing the show's own session.
            guard case .setSession(let id, _, _) = operation else { return false }
            return id == LocalConstellation.showSessionID
        }
    }

    // MARK: Adopting staged imports (LAB-007 Share Ingress Station)

    /// Adds one reviewed import to a collection through `ImportAdopter` over this service.
    ///
    /// `adapter` is fixed by the folder the import waits in, never by its content: the app UI for
    /// the host's own paste and file-picker imports, the share extension for anything another app
    /// shared. The person's Add is the authority, so a grant is issued for exactly the operation
    /// this import maps to, for that adapter and the chosen collection, and revoked when the
    /// commit returns. The adopter validates the import again and checks the grant, and the
    /// service's policy checks it once more at commit (ADR-013).
    func adoptImport(
        _ id: StagingID,
        from inbox: any StagingInbox,
        as adapter: AdapterKind,
        into collection: CollectionID
    ) async throws(ImportRejection) -> ImportAdoption {
        guard adapter == .appUI || adapter == .shareExtension else { throw .notAuthorized }
        let record = try await inbox.validatedRecord(id)
        let operation = try ImportAdopter.operation(for: record, into: collection)
        let grant = try? grants.issue(for: operation, to: adapter, lifetime: .seconds(30))
        defer { if let grant { grants.revoke(grant.id) } }
        return try await ImportAdopter(service: service, inbox: inbox, ledger: grants, adapter: adapter)
            .adopt(id, into: collection)
    }

    // MARK: Reads for other in-app adapters (Action Atlas)

    func collection(_ id: CollectionID, as actor: ActorScope) async throws(OperationError) -> LabCollection {
        try await service.findCollection(id, as: actor)
    }

    func item(_ id: ItemID, as actor: ActorScope) async throws(OperationError) -> LabItem {
        try await service.findItem(id, as: actor)
    }

    func items(_ filter: ItemFilter, as actor: ActorScope) async throws(OperationError) -> [LabItem] {
        try await service.findItems(filter, as: actor)
    }

    /// A session's state, or `nil` when it was never started (LAB-004 Surface Deck).
    func session(_ id: SessionID, as actor: ActorScope) async throws(OperationError) -> LabSession? {
        try await service.findSession(id, as: actor)
    }

    /// Every lab alert (LAB-043). The table holds only lab-owned demo rows.
    func attentions(as actor: ActorScope) async throws(OperationError) -> [LabAttention] {
        try await service.findAttentions(as: actor)
    }

    /// One job (LAB-032 Render That Survives).
    func job(_ id: JobID, as actor: ActorScope) async throws(OperationError) -> LabJob {
        try await service.findJob(id, as: actor)
    }

    /// Every job of one kind.
    func jobs(kind: JobKind, as actor: ActorScope) async throws(OperationError) -> [LabJob] {
        try await service.findJobs(kind: kind, as: actor)
    }

    /// Every lab-owned anchor, ordered by title (LAB-023 Tabletop Reality).
    func anchors(as actor: ActorScope) async throws(OperationError) -> [LabAnchor] {
        try await service.findAnchors(as: actor)
    }

    /// Validates an operation as `actor` without committing or recording anything (LAB-010 Typed
    /// Local Intelligence proposes as the model-tool adapter, which can never commit).
    func propose(_ operation: DomainOperation, as actor: ActorScope) async throws(OperationError) -> OperationProposal {
        try await service.propose(operation, as: actor)
    }

    /// The receipt recorded for a request, or `nil` (LAB-008 Portable Objects: an import retry
    /// returns its recorded receipt instead of planning again).
    func receipt(for requestID: RequestID, as actor: ActorScope) async throws(OperationError) -> ActionReceipt? {
        try await service.findReceipt(for: requestID, as: actor)
    }

    /// Every collection, each read through the service as `actor`.
    ///
    /// The service has no read that lists collections, so the store is asked for identifiers only,
    /// as the census asks it for counts; every collection's content then comes from an authorized
    /// `findCollection`. Replace this with a service read when LabDomain gains one.
    func collections(as actor: ActorScope) async throws(OperationError) -> [LabCollection] {
        let identifiers: [CollectionID]
        do {
            identifiers = try await store.collections().map(\.id)
        } catch {
            throw .storeFailure(.readFailed)
        }
        var collections: [LabCollection] = []
        for id in identifiers {
            do {
                collections.append(try await service.findCollection(id, as: actor))
            } catch .notFound {
                continue
            }
        }
        return collections
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
