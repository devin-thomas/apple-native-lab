import Foundation
import LabDomain
import Testing
@testable import LocalModelBench

struct BenchLab {
    let store = InMemoryOperationStore()
    let ledger = GrantLedger()
    let service: OperationService
    let demoItem: ItemID

    static func make() async throws -> BenchLab {
        try await BenchLab()
    }

    private init() async throws {
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
        let demoCollection = CollectionID(rawValue: UUID(uuidString: "0D3A0000-0000-4000-8000-000000000001")!)
        demoItem = ItemID(rawValue: UUID(uuidString: "0D3A0000-0000-4000-8000-000000000002")!)
        let seed = try DemoSeed(
            version: 1,
            collections: [CollectionDraft(id: demoCollection, title: EntityTitle("Swatches"))],
            items: [ItemDraft(id: demoItem, in: demoCollection, title: EntityTitle("Amber"), note: ItemNote("Warm."))]
        )
        let reset = DomainOperation.resetDemo(seed: seed)
        let grant = try ledger.issue(for: reset, to: .appUI)
        _ = try await service.perform(OperationRequest(
            id: RequestID(), operation: reset, actor: LocalModelBench.appUI
        ))
        ledger.revoke(grant.id)
    }

    func backend(actor: ActorScope, issueGrants: Bool) -> BenchServiceBackend {
        BenchServiceBackend(service: service, actor: actor, ledger: ledger, issueGrants: issueGrants)
    }

    func recorder(actor: ActorScope = LocalModelBench.appUI, issueGrants: Bool = true) -> BenchRecorder {
        BenchRecorder(backend: backend(actor: actor, issueGrants: issueGrants))
    }

    func itemCount() async -> Int {
        await store.items(in: nil).count
    }
}

actor LoadSpy {
    private(set) var calls = 0
    func load(_ admission: LoadAdmission) async -> LoadedModel {
        calls += 1
        _ = admission
        return LoadedModel(allocatedBytes: 0, inference: false)
    }
}

enum BenchFixtures {
    static let machine = MachineStamp(operatingSystem: "fixture-os")
    static let roomy: UInt64 = 8_000_000_000

    static func measured(_ thermal: ThermalClass, scripts: [String: CaseScript] = [:], spy: LoadSpy? = nil) async throws -> BenchReport {
        let executor = FixtureExecutor { admission in
            if let spy { return await spy.load(admission) }
            return LoadedModel(allocatedBytes: 0, inference: false)
        }
        return try await executor.run(
            phase: .measured, thermal: thermal, availableBytes: roomy, scripts: scripts, machine: machine
        )
    }
}
