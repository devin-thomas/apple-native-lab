import Foundation
import LabDomain
import Testing
@testable import ModelRouting

enum Repository {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ModelRoutingTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabFeatures
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()

    static var fixtureURL: URL {
        root.appending(path: "Fixtures/routing/routing-sample-prompt.txt")
    }

    static func fixturePrompt() throws -> String {
        try RoutingFixture.samplePrompt.load(at: fixtureURL)
    }

    static func demoSeed() throws -> DemoSeed {
        struct File: Decodable {
            struct Collection: Decodable { let id: UUID; let title: String }
            struct Item: Decodable { let id: UUID; let collection: UUID; let title: String; let note: String }
            let seedVersion: Int
            let collections: [Collection]
            let items: [Item]
        }
        let file = try JSONDecoder().decode(
            File.self,
            from: Data(contentsOf: root.appending(path: "Fixtures/demo/seed.json"))
        )
        return try DemoSeed(
            version: file.seedVersion,
            collections: try file.collections.map {
                CollectionDraft(id: CollectionID(rawValue: $0.id), title: try EntityTitle($0.title))
            },
            items: try file.items.map {
                ItemDraft(
                    id: ItemID(rawValue: $0.id),
                    in: CollectionID(rawValue: $0.collection),
                    title: try EntityTitle($0.title),
                    note: try ItemNote($0.note)
                )
            }
        )
    }
}

/// Fully open PCC eligibility for tests that need the cloud route reachable.
func openPCC(
    quota: QuotaState = .belowLimit(approaching: false)
) -> PCCEligibility {
    PCCEligibility(
        entitlement: RouteGate(.entitlement, .open, "Test build declares the PCC entitlement."),
        program: RouteGate(.program, .open, "Test claims Small Business Program enrollment."),
        distribution: RouteGate(.distribution, .open, "Test claims permitted distribution."),
        availability: RouteGate(.availability, .open, "PrivateCloudComputeLanguageModel.availability is .available."),
        quota: quota.gate
    )
}

func closedEntitlementPCC(quota: QuotaState = .belowLimit(approaching: false)) -> PCCEligibility {
    var eligibility = openPCC(quota: quota)
    eligibility = PCCEligibility(
        entitlement: RouteGate(
            .entitlement, .closed,
            "This CoreLocal build does not carry \(ModelRouting.pccEntitlement)."
        ),
        program: eligibility.program,
        distribution: eligibility.distribution,
        availability: eligibility.availability,
        quota: eligibility.quota
    )
    return eligibility
}

struct RoutingLab {
    let store: InMemoryOperationStore
    let service: OperationService
    let ledger: GrantLedger
    let backend: ServiceRoutingBackend
    let transport: CountingCloudTransport
    let flow: ModelRoutingFlow
    let events: CollectingDiagnosticSink

    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    static func seeded(
        policy: RoutingPolicy = .localOnly,
        onDevice: OnDeviceAvailability = OnDeviceAvailability(isAvailable: true, detail: "Test on-device available."),
        pcc: PCCEligibility = .coreLocalDefault()
    ) async throws -> RoutingLab {
        let store = InMemoryOperationStore()
        let ledger = GrantLedger()
        let service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
        let reset = DomainOperation.resetDemo(seed: try Repository.demoSeed())
        let grant = try ledger.issue(for: reset, to: .appUI)
        _ = try await service.perform(OperationRequest(id: RequestID(), operation: reset, actor: appUI))
        ledger.revoke(grant.id)

        let events = CollectingDiagnosticSink()
        let transport = CountingCloudTransport()
        let resolver = RouteResolver(policy: policy, onDevice: onDevice, pcc: pcc)
        let flow = ModelRoutingFlow(
            resolver: resolver,
            transport: transport,
            diagnostics: DiagnosticsLog(sinks: [events])
        )
        let backend = ServiceRoutingBackend(service: service)
        return RoutingLab(
            store: store, service: service, ledger: ledger, backend: backend,
            transport: transport, flow: flow, events: events
        )
    }
}

/// Host-shaped backend over `OperationService` for authorization tests.
struct ServiceRoutingBackend: ModelRoutingBackend {
    let service: OperationService

    func demoItems() async throws(ModelRoutingError) -> [LabItem] {
        do {
            let filter = try ItemFilter(includeArchived: true, limit: 200)
            let items = try await service.findItems(filter, as: ModelRouting.proposer)
            return items.filter { $0.namespace == .demo }
        } catch {
            throw .unavailable("The lab store could not be read.")
        }
    }

    func propose(_ operation: DomainOperation) async throws(ModelRoutingError) -> OperationProposal {
        do {
            return try await service.propose(operation, as: ModelRouting.proposer)
        } catch {
            throw .unavailable("The proposal was refused.")
        }
    }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID
    ) async throws(ModelRoutingError) -> ActionReceipt {
        do {
            return try await service.perform(
                OperationRequest(id: requestID, operation: operation, actor: RoutingLab.appUI)
            )
        } catch {
            throw .unavailable("The commit was refused.")
        }
    }
}
