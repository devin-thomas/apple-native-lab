import Foundation
import LabDomain
import Testing

/// CORE-002 acceptance: a stale revision returns an inspectable conflict.
@Suite struct ConflictTests {
    @Test func aStaleRevisionReturnsAnInspectableConflictAndOverwritesNothing() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        try await lab.perform(.updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber study")))
        let before = await lab.appliedCommits

        let requestID = RequestID()
        let stale = DomainOperation.updateItem(id: item.id, expected: .initial, changes: try ItemChanges(title: "Stale title"))
        let receipt = try await lab.perform(stale, id: requestID)

        let conflict = try #require(receipt.conflict)
        #expect(conflict.entity == .item(item.id))
        #expect(conflict.expected == .initial)
        #expect(conflict.current == .r(2))
        #expect(receipt.changes.isEmpty)
        #expect(receipt.undo == nil)
        #expect(receipt.admitted.operation == stale)
        #expect(receipt.summary == "Not applied because item “Amber study” changed: expected revision 1, found 2.")

        let current = try await lab.item(item.id)
        #expect(current.title == "Amber study")
        #expect(current.revision == .r(2))

        // The conflict is recorded with no entity change, so a retry gets the same answer.
        #expect(await lab.appliedCommits == before + 1)
        #expect(try await lab.perform(stale, id: requestID) == receipt)
        #expect(await lab.appliedCommits == before + 1)
    }

    @Test func aStaleArchiveIsAConflictNotAnArchive() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        try await lab.perform(.updateItem(id: item.id, expected: .initial, changes: ItemChanges(note: "Newer")))

        let receipt = try await lab.perform(.archiveItem(id: item.id, expected: .initial))
        #expect(receipt.conflict?.current == .r(2))
        #expect(try await !lab.item(item.id).isArchived)
    }

    @Test func aPersonCanRebaseAConflictUnderANewRequestID() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        try await lab.perform(.updateItem(id: item.id, expected: .initial, changes: ItemChanges(note: "Newer")))
        let conflicted = try await lab.perform(
            .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber study"))
        )
        let conflict = try #require(conflicted.conflict)

        let rebased = conflicted.admitted.operation.rebased(onto: conflict.current)
        let receipt = try await lab.perform(rebased)
        #expect(receipt.status == .committed)
        let current = try await lab.item(item.id)
        #expect(current.title == "Amber study")
        #expect(current.note == "Newer")
        #expect(current.revision == .r(3))
    }

    @Test func concurrentWritersFromTheSameBaseProduceOneCommitAndConflicts() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)

        let receipts = try await withThrowingTaskGroup(of: ActionReceipt.self) { group in
            for writer in 0..<12 {
                group.addTask {
                    try await lab.perform(
                        .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: EntityTitle("Writer \(writer)")))
                    )
                }
            }
            return try await group.reduce(into: [ActionReceipt]()) { $0.append($1) }
        }

        #expect(receipts.filter { $0.status == .committed }.count == 1)
        #expect(receipts.filter { $0.conflict?.current == .r(2) }.count == 11)
        #expect(try await lab.item(item.id).revision == .r(2))
    }

    @Test func aWriterInAnotherProcessBetweenReadAndCommitCausesAConflict() async throws {
        // Two services over one store stand in for the app and an extension process.
        let shared = SpyStore()
        let app = Harness(store: shared)
        let otherProcess = OperationService(store: shared)
        let samples = try await app.makeCollection()
        let item = try await app.makeItem(in: samples)

        await shared.runBeforeNextCommit {
            _ = try? await otherProcess.perform(OperationRequest(
                id: RequestID(),
                operation: .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "From the extension")),
                actor: .granted(.shareExtension)
            ))
        }
        let receipt = try await app.perform(
            .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "From the app"))
        )

        #expect(receipt.conflict?.current == .r(2))
        #expect(try await app.item(item.id).title == "From the extension")
    }

    @Test func undoIsPinnedToTheRevisionItProduced() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let rename = try await lab.perform(
            .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber study"))
        )
        try await lab.perform(.updateItem(id: item.id, expected: .r(2), changes: ItemChanges(note: "Later edit")))

        let lateUndo = try await lab.perform(try #require(rename.undo))
        #expect(lateUndo.conflict?.expected == .r(2))
        #expect(lateUndo.conflict?.current == .r(3))
        #expect(try await lab.item(item.id).title == "Amber study")
    }
}
