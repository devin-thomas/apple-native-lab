import FindTheThing
import Foundation
import LabDomain
import Testing

enum Actors {
    static let app = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    static let model = ActorScope(adapter: .modelTool, grants: Set(Permission.allCases))
    static let reader = ActorScope(adapter: .appUI, grants: [.read])
}

struct ScriptedRetriever: SemanticRetriever {
    let isAvailable: Bool
    let ids: [SearchRecordID]
    var onRetrieve: (@Sendable () async -> Void)?

    func retrieve(_ query: String, limit: Int) async -> [SearchRecordID] {
        await onRetrieve?()
        return ids
    }
}

actor RecordingDonor: AppIndexDonor {
    private(set) var present: [SearchDocument] = []
    private(set) var removed: [SearchRecordID] = []

    func sync(present: [SearchDocument], removed: [SearchRecordID]) async -> DonationReport {
        self.present = present
        self.removed = removed
        return DonationReport(indexed: present.count, removed: removed.count, status: .donated)
    }
}

/// An in-memory lab with the host's grant rule, for a record that is also a lab item.
struct TestLab {
    let ledger = GrantLedger()
    let service: OperationService

    init() {
        service = OperationService(store: InMemoryOperationStore(), policy: GrantAuthorizationPolicy(ledger: ledger))
    }

    func perform(_ operation: DomainOperation, requestID: RequestID = RequestID()) async throws -> ActionReceipt {
        var grant: GrantID?
        if GrantRequirement.sensitiveCommits.requiresGrant(operation.kind, from: .appUI) {
            grant = try ledger.issue(for: operation, to: .appUI, lifetime: .seconds(30)).id
        }
        defer { if let grant { ledger.revoke(grant) } }
        return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: Actors.app))
    }

    func backend() -> ServiceFindBackend {
        ServiceFindBackend(service: service, ledger: ledger)
    }
}

func loadedOperation(
    retriever: any SemanticRetriever = UnavailableSemanticRetriever(),
    backend: any FindTheThingBackend = UnavailableFindBackend(),
    donor: any AppIndexDonor = IdleAppIndexDonor()
) async throws -> FindTheThingOperation {
    let operation = FindTheThingOperation(backend: backend, retriever: retriever, donor: donor)
    let audit = try await operation.reindex(MessyCollection.corpus, as: Actors.app)
    #expect(audit.indexed == 5)
    #expect(audit.skippedNotOptedIn == 1)
    #expect(audit.removed == 0)
    return operation
}
