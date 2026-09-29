import Foundation
import LabDomain
import Testing

/// CORE-002 acceptance: the same request ID and payload cannot mutate twice, and a reused request
/// ID with a different payload is refused.
@Suite struct IdempotencyTests {
    @Test func theSameRequestTwiceMutatesOnceAndReturnsTheOriginalReceipt() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let before = await lab.appliedCommits
        let request = try OperationRequest(
            id: RequestID(),
            operation: .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber study")),
            actor: .appUI
        )

        let first = try await lab.service.perform(request)
        let second = try await lab.service.perform(request)

        #expect(second == first)
        #expect(await lab.appliedCommits == before + 1)
        #expect(try await lab.item(item.id).revision == .r(2))
    }

    @Test func aReplayAfterLaterChangesReturnsTheOriginalReceiptWithoutTouchingState() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let requestID = RequestID()
        let rename = DomainOperation.updateItem(id: item.id, expected: .initial, changes: try ItemChanges(title: "Amber study"))

        let original = try await lab.perform(rename, id: requestID)
        try await lab.perform(.updateItem(id: item.id, expected: .r(2), changes: ItemChanges(note: "Later edit")))
        let replayed = try await lab.perform(rename, id: requestID)

        #expect(replayed == original)
        let current = try await lab.item(item.id)
        #expect(current.revision == .r(3))
        #expect(current.note == "Later edit")
    }

    @Test func concurrentDuplicatesMutateOnce() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let before = await lab.appliedCommits
        // A creation and an update, each submitted 24 times at once, as a double tap or an
        // adapter retry would. Interleaved attempts must replay, never fail or apply twice.
        let requests = try [
            OperationRequest(
                id: RequestID(),
                operation: .createItem(draft: ItemDraft(in: samples.id, title: "Tapped twice")),
                actor: .appIntent
            ),
            OperationRequest(
                id: RequestID(),
                operation: .updateItem(id: item.id, expected: .initial, changes: ItemChanges(note: "Tapped twice")),
                actor: .appIntent
            ),
        ]

        let receipts = try await withThrowingTaskGroup(of: ActionReceipt.self) { group in
            for request in requests {
                for _ in 0..<24 {
                    group.addTask { try await lab.service.perform(request) }
                }
            }
            return try await group.reduce(into: [ActionReceipt]()) { $0.append($1) }
        }

        #expect(receipts.count == 48)
        #expect(Set(receipts).count == 2)
        #expect(receipts.allSatisfy { $0.status == .committed })
        #expect(await lab.appliedCommits == before + 2)
        #expect(try await lab.service.findItems(ItemFilter(collectionID: samples.id), as: .appUI).count == 2)
        #expect(try await lab.item(item.id).revision == .r(2))
    }

    @Test func aReusedRequestIDWithADifferentPayloadIsRefused() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let item = try await lab.makeItem(in: samples)
        let requestID = RequestID()
        let original = try await lab.perform(
            .updateItem(id: item.id, expected: .initial, changes: ItemChanges(title: "Amber study")), id: requestID
        )
        let before = await lab.appliedCommits

        await #expect(throws: OperationError.requestIDReused(requestID)) {
            try await lab.perform(
                .updateItem(id: item.id, expected: .r(2), changes: ItemChanges(title: "Something else")), id: requestID
            )
        }
        await #expect(throws: OperationError.requestIDReused(requestID)) {
            try await lab.perform(.archiveItem(id: item.id, expected: .r(2)), id: requestID)
        }

        #expect(await lab.appliedCommits == before)
        #expect(try await lab.item(item.id).title == "Amber study")
        #expect(try await lab.service.findReceipt(for: requestID, as: .appUI) == original)
    }

    @Test func aReusedRequestIDFromAnotherAdapterIsRefused() async throws {
        let lab = Harness()
        let requestID = RequestID()
        let create = DomainOperation.createCollection(draft: CollectionDraft(title: "Samples"))
        try await lab.perform(create, as: .appUI, id: requestID)

        await #expect(throws: OperationError.requestIDReused(requestID)) {
            try await lab.perform(create, as: .appIntent, id: requestID)
        }
    }

    @Test func aRetryWithARefreshedGrantStillReplays() async throws {
        let lab = Harness()
        let requestID = RequestID()
        let create = DomainOperation.createCollection(draft: CollectionDraft(title: "Samples"))
        let narrow = ActorScope(adapter: .appUI, grants: [.commit])
        let original = try await lab.perform(create, as: narrow, id: requestID)
        #expect(try await lab.perform(create, as: .appUI, id: requestID) == original)
    }

    @Test func aFailedCommitRecordsNothingAndTheSameRequestCanBeRetried() async throws {
        let lab = Harness()
        let collectionID = CollectionID()
        let request = OperationRequest(
            id: RequestID(),
            operation: .createCollection(draft: CollectionDraft(id: collectionID, title: "Samples")),
            actor: .appUI
        )
        await lab.store.failNextCommitOnce()

        await #expect(throws: OperationError.storeFailure(.commitFailed)) { try await lab.service.perform(request) }
        #expect(try await lab.service.findReceipt(for: request.id, as: .appUI) == nil)
        await #expect(throws: OperationError.notFound(.collection(collectionID))) {
            try await lab.collection(collectionID)
        }

        let receipt = try await lab.service.perform(request)
        #expect(receipt.status == .committed)
        #expect(try await lab.service.perform(request) == receipt)
        #expect(await lab.appliedCommits == 1)
    }
}
