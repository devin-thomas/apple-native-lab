import Foundation
import LabDomain
import Testing
@testable import WalletMoment

/// Saving and updating the sample event card through `OperationService` with receipts.
@Suite struct EventCardOperationTests {
    @Test func savingTheEventCardCommitsThroughTheServiceWithReceipts() async throws {
        let lab = try await TestLab.seeded()
        let preview = SampleEvent.preview()
        let collectionID = CollectionID()
        let itemID = ItemID()
        let ops = try EventCardOperations.saveOperations(for: preview, collectionID: collectionID, itemID: itemID)

        let collectionReceipt = try await lab.backend.commit(ops.collection, requestID: RequestID(), names: [:])
        #expect(collectionReceipt.conflict == nil)
        #expect(collectionReceipt.admitted.adapter == .appUI)

        let itemReceipt = try await lab.backend.commit(ops.item, requestID: RequestID(), names: [:])
        #expect(itemReceipt.conflict == nil)

        let items = try await lab.items(in: collectionID)
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(EventCardOperations.isExperimentOwned(item))
        #expect(item.extras.json.contains("HLF2026:GA42:A38E0001"))
        #expect(item.note.value.contains("display data only"))
    }

    @Test func applyingAnUpdateChangesTheNoteAndKeepsAReceipt() async throws {
        let lab = try await TestLab.seeded()
        let collectionID = CollectionID()
        let itemID = ItemID()
        let ops = try EventCardOperations.saveOperations(
            for: SampleEvent.preview(), collectionID: collectionID, itemID: itemID
        )
        _ = try await lab.backend.commit(ops.collection, requestID: RequestID(), names: [:])
        _ = try await lab.backend.commit(ops.item, requestID: RequestID(), names: [:])

        let update = try EventCardOperations.updateOperation(
            itemID: itemID,
            expected: .initial,
            current: SampleEvent.definition,
            update: SampleEvent.seatUpdate,
            at: SampleEvent.duringEvent
        )
        let receipt = try await lab.backend.commit(update, requestID: RequestID(), names: [:])
        #expect(receipt.conflict == nil)

        let item = try #require(try await lab.items(in: collectionID).first)
        #expect(item.note.value.contains("GA-17"))
        #expect(item.note.value.contains("v2-seat"))
        // Extras are write-once: the creation barcode remains; the note carries the update story.
        #expect(item.extras.json.contains("HLF2026:GA42:A38E0001"))
    }

    @Test func invalidInputIsRefusedBeforeAnythingIsSubmitted() async throws {
        let lab = try await TestLab.seeded()
        let before = try await lab.allUserItems().count
        #expect(throws: WalletMomentError.nothingToUpdate) {
            try EventCardOperations.updateOperation(
                itemID: ItemID(),
                expected: .initial,
                current: SampleEvent.definition,
                update: PassUpdate(updateTag: "v2")
            )
        }
        #expect(try await lab.allUserItems().count == before)
    }

    @Test func cancellationBetweenOperationsLeavesEarlierReceipts() async throws {
        let lab = try await TestLab.seeded()
        let collectionID = CollectionID()
        let itemID = ItemID()
        let ops = try EventCardOperations.saveOperations(
            for: SampleEvent.preview(), collectionID: collectionID, itemID: itemID
        )
        let task = Task {
            var committed = 0
            return try await EventCardOperations.perform([ops.collection, ops.item]) { operation in
                committed += 1
                let receipt = try await lab.perform(operation)
                if committed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                return receipt
            }
        }
        let outcome = try await task.value
        #expect(outcome.wasCancelled)
        #expect(outcome.receipts.count == 1)
        #expect(try await lab.items(in: collectionID).isEmpty)
    }

    @Test func resetArchivesOnlyExperimentOwnedCards() async throws {
        let lab = try await TestLab.seeded()
        let collectionID = CollectionID()
        let itemID = ItemID()
        let ops = try EventCardOperations.saveOperations(
            for: SampleEvent.preview(), collectionID: collectionID, itemID: itemID
        )
        _ = try await lab.perform(ops.collection)
        _ = try await lab.perform(ops.item)

        let mine = CollectionDraft(title: try EntityTitle("Field notes"))
        _ = try await lab.perform(.createCollection(draft: mine))
        let other = ItemDraft(in: mine.id, title: try EntityTitle("Graphite stick"))
        _ = try await lab.perform(.createItem(draft: other))

        let owned = try await lab.allUserItems()
        let reset = EventCardOperations.resetOperations(items: owned)
        #expect(reset.count == 1)
        #expect(reset[0] == .archiveItem(id: itemID, expected: .initial))
        _ = try await lab.perform(reset[0])

        let after = try await lab.allUserItems()
        #expect(after.first { $0.id == itemID }?.isArchived == true)
        #expect(after.first { $0.id == other.id }?.isArchived == false)
    }

    @Test func unavailableSignerPathStillAllowsSavingThePreviewCard() async throws {
        let lab = try await TestLab.seeded()
        let signer = UnavailablePassSigner()
        await #expect(throws: WalletMomentError.signingUnavailable) {
            try await signer.signedPass(for: SampleEvent.definition)
        }
        let ops = try EventCardOperations.saveOperations(for: SampleEvent.preview())
        _ = try await lab.backend.commit(ops.collection, requestID: RequestID(), names: [:])
        let receipt = try await lab.backend.commit(ops.item, requestID: RequestID(), names: [:])
        #expect(receipt.conflict == nil)
    }
    @Test func deniedActorCannotSaveAnEventCard() async throws {
        let lab = try await TestLab.seeded()
        let backend = ServiceWalletBackend(service: lab.service, actor: ActorScope(adapter: .modelTool, grants: Set(Permission.allCases)))
        let ops = try EventCardOperations.saveOperations(for: SampleEvent.preview())
        await #expect(throws: WalletMomentError.notAuthorized) {
            try await backend.commit(ops.collection, requestID: RequestID(), names: [:])
        }
        #expect(try await lab.allUserItems().isEmpty)
    }

    @Test func duplicateSaveReplaysAndStaleUpdateCannotOverwrite() async throws {
        let lab = try await TestLab.seeded()
        let ops = try EventCardOperations.saveOperations(for: SampleEvent.preview())
        _ = try await lab.perform(ops.collection)
        let request = RequestID()
        let first = try await lab.perform(ops.item, requestID: request)
        let replay = try await lab.perform(ops.item, requestID: request)
        #expect(first == replay)
        #expect(try await lab.allUserItems().count == 1)
        let update = try EventCardOperations.updateOperation(
            itemID: ops.itemID, expected: .initial, current: SampleEvent.definition,
            update: SampleEvent.seatUpdate, at: SampleEvent.duringEvent
        )
        _ = try await lab.perform(update)
        let stale = try await lab.perform(update)
        #expect(stale.conflict != nil)
        #expect(try await lab.allUserItems().first?.note.value.contains("GA-17") == true)
    }

}
