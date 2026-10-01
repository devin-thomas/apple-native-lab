import Foundation
import LabDomain
import Testing
@testable import AudioWorkshop

/// Saving a preset is the workshop's one change to the lab's data. It goes through
/// `OperationService` with the host's authorization policy and leaves a receipt.
@Suite struct PresetStoreTests {
    @Test func aSaveCreatesTheCollectionOnceAndCommitsTheItemWithAReceipt() async throws {
        let backend = ServicePresetBackend()
        let store = PresetStore(backend: backend)
        let first = try PresetSaveRequest(named: "Dark Pulse", preset: PresetTests.sample)
        let receipt = try await store.save(first)
        #expect(receipt.status == .committed)
        #expect(receipt.admitted.adapter == .appUI)
        #expect(receipt.changes.map(\.entity) == [.item(first.itemID)])
        // Undo archives the preset: the person's data is never deleted.
        #expect(receipt.undo == .archiveItem(id: first.itemID, expected: .initial))

        let second = try PresetSaveRequest(named: "Bright", preset: .standard)
        _ = try await store.save(second)
        let creations = backend.receipts.filter { if case .createCollection = $0.admitted.operation { true } else { false } }
        #expect(creations.count == 1)

        let saved = try await store.presets()
        #expect(saved.map(\.title) == ["Bright", "Dark Pulse"])
        #expect(saved.first { $0.id == first.itemID }?.preset == PresetTests.sample)
        let item = try await backend.service.findItem(first.itemID, as: ServicePresetBackend.appUI)
        #expect(item.namespace == .user)
        #expect(item.note.value == PresetTests.sample.summary)
    }

    @Test func aRetryReturnsTheOriginalReceiptAndSavesOneCopy() async throws {
        let backend = ServicePresetBackend()
        let store = PresetStore(backend: backend)
        let request = try PresetSaveRequest(named: "Once", preset: .standard)
        let first = try await store.save(request)
        let retry = try await store.save(request)
        #expect(retry == first)
        #expect(try await store.presets().count == 1)
    }

    @Test func anItemThatIsNotAPresetIsListedAsUnreadableAndNeverLoaded() async throws {
        let backend = ServicePresetBackend()
        let store = PresetStore(backend: backend)
        _ = try await store.save(PresetSaveRequest(named: "Real", preset: .standard))
        let foreign = ItemID()
        _ = try await backend.commit(.createItem(draft: ItemDraft(
            id: foreign, in: AudioWorkshop.presetCollectionID, title: EntityTitle("Imported"),
            extras: ItemExtras(json: #"{"audioWorkshopPreset":{"format":"native-lab-audio-preset","schemaVersion":9}}"#)
        )), requestID: RequestID(), names: [:])
        let listed = try await store.presets()
        let unreadable = try #require(listed.first { $0.id == foreign })
        #expect(unreadable.preset == nil)
        #expect(throws: PresetRejection.newerVersion(9)) { try unreadable.content.get() }
    }

    @Test func anArchivedPresetCollectionRefusesTheSaveAndSaysHowToFixIt() async throws {
        let backend = ServicePresetBackend()
        let store = PresetStore(backend: backend)
        _ = try await store.save(PresetSaveRequest(named: "First", preset: .standard))
        // Archiving is destructive, so it needs a grant, as a person's confirmation gives one.
        let archive = DomainOperation.archiveCollection(id: AudioWorkshop.presetCollectionID, expected: .initial)
        _ = try backend.ledger.issue(for: archive, to: .appUI)
        _ = try await backend.commit(archive, requestID: RequestID(), names: [:])

        let error = await #expect(throws: PresetStoreError.self) {
            try await store.save(PresetSaveRequest(named: "Second", preset: .standard))
        }
        #expect(error?.message.contains("archived") == true)
        #expect(backend.receipts.count == 3)
    }

    @Test func aModelToolCannotSaveAPreset() async throws {
        let backend = ServicePresetBackend(actor: ActorScope(adapter: .modelTool, grants: Set(Permission.allCases)))
        let store = PresetStore(backend: backend)
        let error = await #expect(throws: PresetStoreError.self) {
            try await store.save(PresetSaveRequest(named: "Sneaky", preset: .standard))
        }
        guard case .refused(.unauthorized) = error else {
            Issue.record("expected an authorization refusal, got \(String(describing: error))")
            return
        }
        #expect(backend.receipts.isEmpty)
    }

    @Test func aNameIsValidatedBeforeAnythingIsCommitted() {
        #expect(throws: PresetStoreError.invalidName(.emptyTitle)) { try PresetSaveRequest(named: "   ", preset: .standard) }
        #expect(throws: PresetStoreError.invalidName(.titleTooLong(limit: EntityTitle.maximumLength))) {
            try PresetSaveRequest(named: String(repeating: "a", count: 121), preset: .standard)
        }
        #expect(PresetStoreError.invalidName(.emptyTitle).message == "Give the preset a name.")
    }

    @Test func aCancelledSaveCommitsNothing() async throws {
        let backend = ServicePresetBackend()
        let store = PresetStore(backend: backend)
        let request = try PresetSaveRequest(named: "Never", preset: .standard)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.save(request)
        }
        await #expect(throws: PresetStoreError.cancelled) { try await task.value }
        #expect(backend.receipts.isEmpty)
    }
}
