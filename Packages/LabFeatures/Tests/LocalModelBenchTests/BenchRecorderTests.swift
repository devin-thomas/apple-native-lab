import LabDomain
import Testing
@testable import LocalModelBench

/// Recording and reset go through the operation service. A refusal writes nothing new.
@Suite struct BenchRecorderTests {
    @Test func recordingProducesAReceiptAndARetryDoesNotDuplicate() async throws {
        let lab = try await BenchLab.make()
        let report = try await BenchFixtures.measured(.cold)
        let recorder = lab.recorder()
        let first = try await recorder.record(report)
        let second = try await recorder.record(report)
        #expect(first.admitted.operation.kind == .createItem)
        #expect(first.status == .committed)
        #expect(first.operationID == second.operationID)
        let items = await lab.store.items(in: LocalModelBench.resultsCollectionID)
        #expect(items.count == 1)
        #expect(items[0].namespace == .user)
        #expect(BenchRecorder.isBenchReport(items[0].extras))
        #expect(items[0].note.value.contains("not inference"))
        let demo = await lab.store.item(lab.demoItem)
        #expect(demo?.isArchived == false)
    }

    @Test func aModelToolCannotRecord() async throws {
        let lab = try await BenchLab.make()
        let before = await lab.itemCount()
        let report = try await BenchFixtures.measured(.warm)
        let recorder = lab.recorder(actor: LocalModelBench.modelTool, issueGrants: false)
        await #expect(throws: BenchError.unauthorized) {
            try await recorder.record(report)
        }
        #expect(await lab.itemCount() == before)
        #expect(await lab.store.collections().allSatisfy { $0.namespace == .demo })
    }

    @Test func anUnavailableLabRecordsNothing() async throws {
        let lab = try await BenchLab.make()
        let before = await lab.itemCount()
        let recorder = BenchRecorder(backend: ClosedBench())
        let report = try await BenchFixtures.measured(.cold)
        await #expect(throws: BenchError.unavailable) {
            try await recorder.record(report)
        }
        #expect(await lab.itemCount() == before)
    }

    @Test func aFailedRunCanBeStoredAndStillHasNoScore() async throws {
        let lab = try await BenchLab.make()
        let failed = try await BenchFixtures.measured(.cold, scripts: [
            "sum-nineteen": CaseScript(text: "0", latencyNanoseconds: 1),
        ])
        #expect(throws: BenchError.failedTask) { try failed.score() }
        let receipt = try await lab.recorder().record(failed)
        #expect(receipt.status == .committed)
        let item = try #require(await lab.store.items(in: LocalModelBench.resultsCollectionID).first)
        #expect(item.note.value.contains("No score."))
        #expect(!item.note.value.contains("median"))
    }

    @Test func resetArchivesOnlyBenchReports() async throws {
        let lab = try await BenchLab.make()
        let otherCollection = CollectionID()
        let otherItem = ItemID()
        _ = try await lab.service.perform(OperationRequest(
            id: RequestID(),
            operation: .createCollection(draft: CollectionDraft(id: otherCollection, title: EntityTitle("Notes"))),
            actor: LocalModelBench.appUI
        ))
        _ = try await lab.service.perform(OperationRequest(
            id: RequestID(),
            operation: .createItem(draft: ItemDraft(
                id: otherItem, in: otherCollection, title: EntityTitle("Field note"), note: ItemNote("Kept.")
            )),
            actor: LocalModelBench.appUI
        ))
        let report = try await BenchFixtures.measured(.warm)
        _ = try await lab.recorder().record(report)
        let receipts = try await lab.recorder().reset()
        #expect(receipts.count == 1)
        #expect(receipts[0].admitted.operation.kind == .archiveItem)
        #expect(receipts[0].admitted.adapter == .appUI)
        let bench = try #require(await lab.store.items(in: LocalModelBench.resultsCollectionID).first)
        #expect(bench.isArchived)
        #expect(await lab.store.item(otherItem)?.isArchived == false)
        #expect(await lab.store.item(lab.demoItem)?.isArchived == false)
        let again = try await lab.recorder().reset()
        #expect(again.isEmpty)
    }

    @Test func resetWithoutAGrantLeavesTheReport() async throws {
        let lab = try await BenchLab.make()
        let report = try await BenchFixtures.measured(.cold)
        _ = try await lab.recorder().record(report)
        let denied = lab.recorder(issueGrants: false)
        await #expect(throws: BenchError.unauthorized) {
            try await denied.reset()
        }
        let bench = try #require(await lab.store.items(in: LocalModelBench.resultsCollectionID).first)
        #expect(!bench.isArchived)
        #expect(await lab.store.item(lab.demoItem)?.isArchived == false)
    }
}

private struct ClosedBench: LocalModelBenchBackend {
    func collection(_ id: CollectionID) async throws(BenchError) -> LabCollection? { throw .unavailable }
    func items(in collection: CollectionID) async throws(BenchError) -> [LabItem] { throw .unavailable }
    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(BenchError) -> ActionReceipt { throw .unavailable }
}
