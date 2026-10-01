import LabDomain
import Testing
@testable import LocalModelBench

/// A reset uses the revisions it read; a change between read and commit must survive.
@Suite struct BenchQualificationTests {
    @Test func staleResetReturnsConflictAndLeavesTheChangedReport() async throws {
        let lab = try await BenchLab.make()
        let report = try await BenchFixtures.measured(.cold)
        _ = try await lab.recorder().record(report)
        let backend = ChangingBench(underlying: lab.backend(actor: LocalModelBench.appUI, issueGrants: true))
        let receipts = try await BenchRecorder(backend: backend).reset()
        #expect(receipts.count == 1)
        guard case .conflict = receipts[0].status else {
            Issue.record("A stale reset must return a conflict receipt")
            return
        }
        let item = try #require(await lab.store.items(in: LocalModelBench.resultsCollectionID).first)
        #expect(!item.isArchived && item.title.value == "Changed after reset read")
        #expect(await lab.store.item(lab.demoItem)?.isArchived == false)
        let retry = try await lab.recorder().reset()
        #expect(retry.count == 1 && retry[0].status == .committed)
    }

    @Test func retryingARecordedReportAfterResetDoesNotRestoreIt() async throws {
        let lab = try await BenchLab.make()
        let report = try await BenchFixtures.measured(.cold)
        let original = try await lab.recorder().record(report)
        _ = try await lab.recorder().reset()
        let retry = try await lab.recorder().record(report)
        #expect(retry.operationID == original.operationID)
        let items = await lab.store.items(in: LocalModelBench.resultsCollectionID)
        #expect(items.count == 1 && items[0].isArchived)
    }
}

private struct ChangingBench: LocalModelBenchBackend {
    let underlying: BenchServiceBackend

    func collection(_ id: CollectionID) async throws(BenchError) -> LabCollection? {
        try await underlying.collection(id)
    }

    func items(in collection: CollectionID) async throws(BenchError) -> [LabItem] {
        let snapshot = try await underlying.items(in: collection)
        if let item = snapshot.first {
            let changes: ItemChanges
            do { changes = try ItemChanges(title: EntityTitle("Changed after reset read")) } catch { throw .unavailable }
            _ = try await underlying.commit(.updateItem(id: item.id, expected: item.revision,
                                                        changes: changes),
                                             requestID: RequestID(), names: [:])
        }
        return snapshot
    }

    func commit(_ operation: DomainOperation, requestID: RequestID,
                names: [EntityReference: String]) async throws(BenchError) -> ActionReceipt {
        try await underlying.commit(operation, requestID: requestID, names: names)
    }
}
