import ActionAtlas
import Foundation
import LabDomain
import Synchronization

/// A backend with the host's rules over an in-memory store: every read and commit goes through
/// `OperationService` with `GrantAuthorizationPolicy`, and a grant is issued only for a control
/// press in the app or an intent holding a confirmation of exactly that operation.
final class TestBackend: ActionAtlasBackend {
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    static let appIntent = ActorScope(adapter: .appIntent, grants: Set(Permission.allCases))

    let store = InMemoryOperationStore()
    let ledger = GrantLedger()
    let service: OperationService
    /// Every commit this backend was asked for, in order.
    let commits = Mutex<[(DomainOperation, AtlasAuthority)]>([])

    init() {
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
    }

    /// A backend holding `TestSeed.seed` in its demo namespace.
    static func seeded() async throws -> TestBackend {
        let backend = TestBackend()
        let operation = DomainOperation.resetDemo(seed: TestSeed.seed)
        let grant = try backend.ledger.issue(for: operation, to: .appUI)
        defer { backend.ledger.revoke(grant.id) }
        _ = try await backend.service.perform(OperationRequest(id: RequestID(), operation: operation, actor: appUI))
        return backend
    }

    var link: ActionAtlasLink { ActionAtlasLink(backend: self) }

    func actions(_ entryPoint: AtlasEntryPoint) -> ActionAtlasActions {
        ActionAtlasActions(backend: self, entryPoint: entryPoint)
    }

    var commitCount: Int { commits.withLock { $0.count } }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        authority: AtlasAuthority,
        names: [EntityReference: String]
    ) async throws(ActionAtlasError) -> ActionReceipt {
        commits.withLock { $0.append((operation, authority)) }
        let actor = Self.actor(authority.entryPoint)
        var grant: GrantID?
        if GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: actor.adapter) && Self.permits(authority, operation) {
            grant = try? ledger.issue(for: operation, to: actor.adapter, lifetime: .seconds(30)).id
        }
        defer { if let grant { ledger.revoke(grant) } }
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw ActionAtlasError(error)
        }
    }

    func collection(_ id: CollectionID, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> LabCollection {
        do { return try await service.findCollection(id, as: Self.actor(entryPoint)) } catch { throw ActionAtlasError(error) }
    }

    func item(_ id: ItemID, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> LabItem {
        do { return try await service.findItem(id, as: Self.actor(entryPoint)) } catch { throw ActionAtlasError(error) }
    }

    func items(_ filter: ItemFilter, via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> [LabItem] {
        do { return try await service.findItems(filter, as: Self.actor(entryPoint)) } catch { throw ActionAtlasError(error) }
    }

    func collections(via entryPoint: AtlasEntryPoint) async throws(ActionAtlasError) -> [LabCollection] {
        var found: [LabCollection] = []
        for id in await store.collections().map(\.id) {
            found.append(try await collection(id, via: entryPoint))
        }
        return found
    }

    /// The host's grant rule (`LabDataService.mayGrant`) for the authorities Action Atlas uses.
    static func permits(_ authority: AtlasAuthority, _ operation: DomainOperation) -> Bool {
        switch authority {
        case .appControl: true
        case .intent(let confirmation): confirmation?.covers(operation) == true
        }
    }

    static func actor(_ entryPoint: AtlasEntryPoint) -> ActorScope {
        switch entryPoint {
        case .appUI: appUI
        case .appIntent: appIntent
        }
    }

    /// Every stored receipt for these requests.
    func receipts(_ requests: [AtlasRequest]) async -> [ActionReceipt] {
        var found: [ActionReceipt] = []
        for request in requests {
            if let receipt = await store.receipt(for: request.id) { found.append(receipt) }
        }
        return found
    }

    /// The whole persisted entity state, ordered by ID, for comparing two stores.
    func snapshot() async -> (collections: [LabCollection], items: [LabItem]) {
        (
            await store.collections().sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString },
            await store.items(in: nil).sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        )
    }
}

/// A small original demo seed: two collections and three samples.
enum TestSeed {
    static let pigments = CollectionID(rawValue: UUID(uuidString: "0B1D7C57-5B8E-4D8E-9D4A-6E1F4A2B3C01")!)
    static let papers = CollectionID(rawValue: UUID(uuidString: "0B1D7C57-5B8E-4D8E-9D4A-6E1F4A2B3C02")!)
    static let amber = ItemID(rawValue: UUID(uuidString: "0B1D7C57-5B8E-4D8E-9D4A-6E1F4A2B3C11")!)
    static let cobalt = ItemID(rawValue: UUID(uuidString: "0B1D7C57-5B8E-4D8E-9D4A-6E1F4A2B3C12")!)
    static let kraft = ItemID(rawValue: UUID(uuidString: "0B1D7C57-5B8E-4D8E-9D4A-6E1F4A2B3C21")!)

    static let seed: DemoSeed = {
        do {
            return try DemoSeed(
                version: 1,
                collections: [
                    CollectionDraft(id: pigments, title: EntityTitle("Pigment swatches")),
                    CollectionDraft(id: papers, title: EntityTitle("Paper stock")),
                ],
                items: [
                    ItemDraft(id: amber, in: pigments, title: EntityTitle("Amber swatch"), note: ItemNote("Warm yellow-brown.")),
                    ItemDraft(id: cobalt, in: pigments, title: EntityTitle("Cobalt swatch"), note: ItemNote("Deep cool blue.")),
                    ItemDraft(id: kraft, in: papers, title: EntityTitle("Kraft card"), note: ItemNote("Brown and stiff.")),
                ]
            )
        } catch {
            fatalError("the test seed is valid: \(error)")
        }
    }()
}

/// A request with a fixed ID, so two runs can use the same one.
func request(_ index: Int) -> AtlasRequest {
    AtlasRequest(RequestID(rawValue: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!))
}

/// A confirmation step that records its prompts and approves.
final class ConfirmationSpy: Sendable {
    let prompts = Mutex<[ArchivePrompt]>([])

    var count: Int { prompts.withLock { $0.count } }

    @Sendable func approve(_ prompt: ArchivePrompt) async throws {
        prompts.withLock { $0.append(prompt) }
    }

    @Sendable func decline(_ prompt: ArchivePrompt) async throws {
        prompts.withLock { $0.append(prompt) }
        throw CancellationError()
    }
}
