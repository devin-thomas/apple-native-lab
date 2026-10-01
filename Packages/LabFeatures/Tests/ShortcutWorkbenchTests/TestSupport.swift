import ActionAtlas
import Foundation
import LabDomain
import Synchronization
import Testing
@testable import ShortcutWorkbench

/// A backend with the host's rules over an in-memory store.
final class TestWorkbenchBackend: WorkbenchBackend {
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    static let appIntent = ActorScope(adapter: .appIntent, grants: Set(Permission.allCases))

    let store = InMemoryOperationStore()
    let ledger = GrantLedger()
    let service: OperationService
    let commits = Mutex<[(DomainOperation, WorkbenchAuthority)]>([])

    init() {
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
    }

    static func seeded() async throws -> TestWorkbenchBackend {
        let backend = TestWorkbenchBackend()
        let operation = DomainOperation.resetDemo(seed: TestSeed.seed)
        let grant = try backend.ledger.issue(for: operation, to: .appUI)
        defer { backend.ledger.revoke(grant.id) }
        _ = try await backend.service.perform(OperationRequest(id: RequestID(), operation: operation, actor: appUI))
        return backend
    }

    var link: WorkbenchLink { WorkbenchLink(backend: self) }

    func actions(_ entryPoint: WorkbenchEntryPoint, catalog: WorkbenchRecipeCatalog = WorkbenchRecipeCatalog()) -> WorkbenchActions {
        WorkbenchActions(backend: self, entryPoint: entryPoint, catalog: catalog)
    }

    var commitCount: Int { commits.withLock { $0.count } }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        authority: WorkbenchAuthority,
        names: [EntityReference: String]
    ) async throws(WorkbenchError) -> ActionReceipt {
        commits.withLock { $0.append((operation, authority)) }
        let actor = Self.actor(authority.entryPoint)
        // Non-destructive workbench commits need no grant under GrantAuthorizationPolicy for appUI.
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw WorkbenchError(error)
        }
    }

    func item(_ id: ItemID, via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> LabItem {
        do { return try await service.findItem(id, as: Self.actor(entryPoint)) } catch { throw WorkbenchError(error) }
    }

    func items(_ filter: ItemFilter, via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> [LabItem] {
        do { return try await service.findItems(filter, as: Self.actor(entryPoint)) } catch { throw WorkbenchError(error) }
    }

    func collection(_ id: CollectionID, via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> LabCollection {
        do { return try await service.findCollection(id, as: Self.actor(entryPoint)) } catch { throw WorkbenchError(error) }
    }

    func collections(via entryPoint: WorkbenchEntryPoint) async throws(WorkbenchError) -> [LabCollection] {
        var found: [LabCollection] = []
        for id in await store.collections().map(\.id) {
            found.append(try await collection(id, via: entryPoint))
        }
        return found
    }

    static func actor(_ entryPoint: WorkbenchEntryPoint) -> ActorScope {
        switch entryPoint {
        case .appUI: appUI
        case .appIntent: appIntent
        }
    }
}

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
                    CollectionDraft(id: pigments, title: try EntityTitle("Pigments")),
                    CollectionDraft(id: papers, title: try EntityTitle("Papers")),
                ],
                items: [
                    ItemDraft(id: amber, in: pigments, title: try EntityTitle("Amber sample"), note: try ItemNote("Warm yellow ochre.")),
                    ItemDraft(id: cobalt, in: pigments, title: try EntityTitle("Cobalt chip"), note: try ItemNote("Cool blue.")),
                    ItemDraft(id: kraft, in: papers, title: try EntityTitle("Kraft card"), note: try ItemNote("Brown stock.")),
                ]
            )
        } catch {
            fatalError("the test seed is valid: \(error)")
        }
    }()
}
