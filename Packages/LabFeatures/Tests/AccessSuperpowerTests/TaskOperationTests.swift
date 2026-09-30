@testable import AccessSuperpower
import Foundation
import LabDomain
import Testing

/// The task's one operation through the operation service: practice set-up and reset, the restore
/// that finishes the task, and its failures (invalid input, stale state, a duplicate request, and
/// cancellation). Fixture path: an in-memory store behind `OperationService` with
/// `GrantAuthorizationPolicy`, seeded from `Fixtures/demo/seed.json`.
@Suite struct TaskOperationTests {
    let practice = PracticeSet.standard
    static let quartz = ItemID(UUID(uuidString: "AF451890-CA80-4DE9-B18B-4007066C9177")!)
    static let vellum = ItemID(UUID(uuidString: "6933AC83-9E61-4264-8EB8-0535B3C5E0F8")!)
    static let amber = ItemID(UUID(uuidString: "DB666EF1-F642-43F1-B415-895B6ECFF693")!)

    private func practiced() async throws -> TestLab {
        let lab = try await TestLab.seeded()
        let run = try await PracticeRun.perform(practice.setUpOperations(in: lab.tally())) { try await lab.perform($0) }
        #expect(run.receipts.count == 6 && !run.wasCancelled)
        return lab
    }

    @Test func settingUpPracticeArchivesTheSixSamplesWithOneReceiptEach() async throws {
        let lab = try await TestLab.seeded()
        #expect(AccessibleTask.status(of: try await lab.tally(), after: nil) == .nothingArchived)
        let operations = practice.setUpOperations(in: try await lab.tally())
        #expect(operations.map(\.kind) == Array(repeating: .archiveItem, count: 6))
        let run = try await PracticeRun.perform(operations) { try await lab.perform($0) }
        #expect(run.receipts.allSatisfy { $0.conflict == nil && $0.undo?.kind == .restoreItem })
        #expect(PracticeRun.sentence(archiving: true, run, of: 6) == "Archived 6 practice samples. Each has its own receipt.")

        let tally = try await lab.tally()
        #expect(tally.collections.map(\.archivedCount) == [2, 3, 1])
        #expect(tally.leaders.map(\.title) == ["Mineral specimens"])
        #expect(practice.setUpOperations(in: tally).isEmpty, "set-up is idempotent: nothing left to archive")
    }

    /// The restore every path submits: the operation built from the tally commits through the
    /// service with a receipt that offers an undo, and the judgment says the task is done.
    @Test func restoringASampleFromTheLeaderFinishesTheTask() async throws {
        let lab = try await practiced()
        let before = try await lab.tally()
        let operation = try AccessibleTask.restoreOperation(for: Self.quartz, in: before)
        #expect(operation == .restoreItem(id: Self.quartz, expected: Revision.initial.next()))
        let outcome = try #require(AccessibleTask.judge(restoring: Self.quartz, in: before))

        let receipt = try await lab.perform(operation)
        #expect(receipt.conflict == nil)
        #expect(receipt.admitted.adapter == .appUI)
        #expect(receipt.summary == "Restored item “Quartz point”.")
        #expect(receipt.undo == .archiveItem(id: Self.quartz, expected: Revision.initial.next().next()))
        #expect(outcome.completesTask)

        let after = try await lab.tally()
        #expect(after.collections.map(\.archivedCount) == [2, 2, 1])
        #expect(AccessibleTask.status(of: after, after: outcome) == .done)
    }

    @Test func restoringFromAnotherCollectionIsARealChangeThatDoesNotFinishTheTask() async throws {
        let lab = try await practiced()
        let before = try await lab.tally()
        let outcome = try #require(AccessibleTask.judge(restoring: Self.vellum, in: before))
        let receipt = try await lab.perform(try AccessibleTask.restoreOperation(for: Self.vellum, in: before))
        #expect(receipt.conflict == nil)
        #expect(!outcome.completesTask)
        #expect(AccessibleTask.status(of: try await lab.tally(), after: outcome) == .toDo)
    }

    @Test func invalidInputIsRefusedBeforeAnythingIsSubmitted() async throws {
        let lab = try await practiced()
        let tally = try await lab.tally()
        #expect(throws: AccessTaskError.notArchived("Amber swatch")) {
            try AccessibleTask.restoreOperation(for: Self.amber, in: tally)
        }
        #expect(throws: AccessTaskError.notFound) {
            try AccessibleTask.restoreOperation(for: ItemID(), in: tally)
        }
        #expect(AccessibleTask.judge(restoring: Self.amber, in: tally) == nil)
        #expect(AccessTaskError.notArchived("Amber swatch").message == "“Amber swatch” is not archived, so there is nothing to restore. Nothing was changed.")
    }

    /// A person's own data never enters the tally, so it can never be the task's answer or a
    /// practice change.
    @Test func userDataIsNeitherCountedNorRestored() async throws {
        let lab = try await practiced()
        let mine = CollectionDraft(title: try EntityTitle("Field notes"))
        _ = try await lab.perform(.createCollection(draft: mine))
        let item = ItemDraft(in: mine.id, title: try EntityTitle("Graphite stick"))
        _ = try await lab.perform(.createItem(draft: item))
        _ = try await lab.perform(.archiveItem(id: item.id, expected: .initial))

        let collection = try await lab.service.findCollection(mine.id, as: TestLab.appUI)
        let items = try await lab.service.findItems(try ItemFilter(collectionID: mine.id, includeArchived: true), as: TestLab.appUI)
        var groups = seededGroups(try Fixtures.demoSeed())
        groups.append((collection, items))
        let tally = ArchiveTally(groups)
        #expect(tally.collections.count == 3, "only demo collections are counted")
        #expect(throws: AccessTaskError.notFound) { try AccessibleTask.restoreOperation(for: item.id, in: tally) }
    }

    /// The tally the person saw is stale when the sample changed since: the service returns a
    /// conflict receipt and changes nothing.
    @Test func aStaleRestoreChangesNothing() async throws {
        let lab = try await practiced()
        let stale = try await lab.tally()
        _ = try await lab.perform(try AccessibleTask.restoreOperation(for: Self.quartz, in: stale))
        _ = try await lab.perform(.archiveItem(id: Self.quartz, expected: Revision.initial.next().next()))

        let receipt = try await lab.perform(try AccessibleTask.restoreOperation(for: Self.quartz, in: stale))
        #expect(receipt.conflict != nil)
        #expect(receipt.changes.isEmpty)
        #expect(try await lab.tally().sample(Self.quartz)?.sample.isArchived == true, "still archived")
    }

    /// A second press of the same control reuses its request and gets the first receipt back.
    @Test func aDuplicateRequestCommitsOnce() async throws {
        let lab = try await practiced()
        let operation = try AccessibleTask.restoreOperation(for: Self.quartz, in: try await lab.tally())
        let request = RequestID()
        let first = try await lab.perform(operation, requestID: request)
        let second = try await lab.perform(operation, requestID: request)
        #expect(first == second)
        #expect(try await lab.tally().sample(Self.quartz)?.sample.revision == Revision.initial.next().next(), "restored once")
    }

    /// Cancelling set-up between two commits leaves exactly the samples already archived, each with
    /// its receipt, and Reset Practice restores exactly those.
    @Test func cancellingSetUpStopsBetweenCommitsAndResetRestoresWhatWasDone() async throws {
        let lab = try await TestLab.seeded()
        let operations = practice.setUpOperations(in: try await lab.tally())
        let task = Task {
            var committed = 0
            return try await PracticeRun.perform(operations) { operation in
                committed += 1
                if committed == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                return try await lab.perform(operation)
            }
        }
        let run = try await task.value
        #expect(run.wasCancelled)
        #expect(run.receipts.count == 2)
        #expect(PracticeRun.sentence(archiving: true, run, of: 6) == "Stopped after 2 of 6. Archived 2 practice samples; each has its own receipt.")
        let tally = try await lab.tally()
        #expect(tally.totalArchived == 2)

        let reset = try await PracticeRun.perform(practice.resetOperations(in: tally)) { try await lab.perform($0) }
        #expect(reset.receipts.map(\.admitted.operation.kind) == [.restoreItem, .restoreItem])
        #expect(try await lab.tally().totalArchived == 0)
    }

    /// Reset Practice touches only the practice samples: a sample the person archived that is not
    /// in the practice set stays archived.
    @Test func resetPracticeRestoresOnlyThePracticeSamples() async throws {
        let lab = try await practiced()
        _ = try await lab.perform(.archiveItem(id: Self.amber, expected: .initial))
        let operations = practice.resetOperations(in: try await lab.tally())
        #expect(operations.count == 6)
        #expect(!operations.contains { $0.target == .item(Self.amber) })
        let run = try await PracticeRun.perform(operations) { try await lab.perform($0) }
        #expect(PracticeRun.sentence(archiving: false, run, of: 6) == "Restored 6 practice samples. Each has its own receipt.")
        let tally = try await lab.tally()
        #expect(tally.totalArchived == 1)
        #expect(tally.sample(Self.amber)?.sample.isArchived == true)
        #expect(practice.resetOperations(in: tally).isEmpty)
    }
}
