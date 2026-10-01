import ActionAtlas
import ContextCards
import Foundation
import LabDomain
import Synchronization

/// A backend with the host's grant rule over an in-memory store. Context Cards commits through it
/// the way the app commits through `LibraryAtlasBackend`.
final class CardBackend: ActionAtlasBackend {
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    static let appIntent = ActorScope(adapter: .appIntent, grants: Set(Permission.allCases))

    let store = InMemoryOperationStore()
    let ledger = GrantLedger()
    let service: OperationService
    let commits = Mutex<[(DomainOperation, AtlasAuthority)]>([])
    private let storedLink = Mutex<ContextCardsLink?>(nil)

    init() {
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
    }

    static func seeded() async throws -> CardBackend {
        let backend = CardBackend()
        let operation = DomainOperation.resetDemo(seed: CardSeed.seed)
        let grant = try backend.ledger.issue(for: operation, to: .appUI)
        defer { backend.ledger.revoke(grant.id) }
        _ = try await backend.service.perform(OperationRequest(id: RequestID(), operation: operation, actor: appUI))
        return backend
    }

    var link: ContextCardsLink {
        storedLink.withLock { slot in
            if let slot { return slot }
            let created = ContextCardsLink(atlas: ActionAtlasLink(backend: self))
            slot = created
            return created
        }
    }

    func actions(_ entryPoint: AtlasEntryPoint) -> ContextCardsActions {
        link.actions(entryPoint)
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
        if GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: actor.adapter), Self.permits(authority, operation) {
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
}

/// Amber and Cobalt, the two samples the card shows, in a demo namespace of their own.
enum CardSeed {
    static let pigments = CollectionID(rawValue: UUID(uuidString: "C0FFEE00-0002-4000-8000-000000000001")!)
    static let amber = ContextCards.primarySampleID
    static let cobalt = ContextCards.replacementSampleID

    static let seed: DemoSeed = {
        do {
            return try DemoSeed(
                version: 1,
                collections: [CollectionDraft(id: pigments, title: EntityTitle("Pigment swatches"))],
                items: [
                    ItemDraft(id: amber, in: pigments, title: EntityTitle("Amber swatch"), note: ItemNote("Warm yellow-brown.")),
                    ItemDraft(id: cobalt, in: pigments, title: EntityTitle("Cobalt swatch"), note: ItemNote("Deep cool blue.")),
                ]
            )
        } catch {
            fatalError("the context-card seed is valid: \(error)")
        }
    }()
}

func cardRequest(_ index: Int) -> AtlasRequest {
    AtlasRequest(RequestID(rawValue: UUID(uuidString: String(format: "00000000-0002-4000-8000-%012d", index))!))
}

final class CardConfirmation: Sendable {
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
