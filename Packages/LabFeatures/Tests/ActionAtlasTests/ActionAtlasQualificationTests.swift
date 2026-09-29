@testable import ActionAtlas
import Foundation
import LabDomain
import Testing

/// LAB-001-B step 3: denial, cancellation, stale and duplicate state, and a Reset Demo that never
/// touches imported user data. These add to the LAB-001-A suites (`ActionAtlasSafetyTests`,
/// `ActionAtlasIntentTests`) the cases where a refusal, a cancellation, or a stale snapshot is
/// followed by something else: a retry, the other entry point, an import, or a reset.
///
/// Fixture path: an in-memory store behind `OperationService` with `GrantAuthorizationPolicy`,
/// with the intents run through `run(with:)` and the system's dialogs stood in for.
@Suite struct ActionAtlasQualificationTests {
    // MARK: Denial

    /// A refused archive records nothing, so its request ID is still free: once the person
    /// confirms, the same request commits exactly once.
    @Test func aDeniedIntentArchiveCommitsOnceWhenConfirmedUnderTheSameRequest() async throws {
        let backend = try await TestBackend.seeded()
        let archive = DomainOperation.archiveItem(id: TestSeed.amber, expected: .initial)
        await #expect(throws: ActionAtlasError.self) {
            try await backend.commit(archive, requestID: request(1).id, authority: .intent(nil), names: [:])
        }
        #expect(await backend.store.receipt(for: request(1).id) == nil)

        let intent = ArchiveItemIntent()
        intent.item = try await entity(TestSeed.amber, in: backend)
        intent.requestID = request(1).id.description
        let spy = ConfirmationSpy()
        let first = try await intent.run(with: backend.link, confirm: spy.approve)
        let retry = try await intent.run(with: backend.link, confirm: spy.approve)
        #expect(first.receipt == retry.receipt)
        #expect(first.value.isArchived)
        #expect(try await backend.actions(.appUI).item(TestSeed.amber).revision.rawValue == 2, "archived once")
    }

    /// ADR-011: a request ID is bound to the entry point that first used it, so the other entry
    /// point cannot replay it, even for the same change. Nothing is committed twice.
    @Test(arguments: [(AtlasEntryPoint.appUI, AtlasEntryPoint.appIntent), (.appIntent, .appUI)])
    func aRequestIDFromTheOtherEntryPointIsRefused(first: AtlasEntryPoint, second: AtlasEntryPoint) async throws {
        let backend = try await TestBackend.seeded()
        let created = try await backend.actions(first).createCollection(title: "Field notes", request: request(1))
        let error = await #expect(throws: ActionAtlasError.self) {
            try await backend.actions(second).createCollection(title: "Field notes", request: request(1))
        }
        #expect(error == .refused(.requestIDReused(request(1).id)))
        #expect(error?.message == "That request ID was already used for a different change. Use a new request ID. Nothing was changed.")
        #expect(await backend.store.collections().filter { $0.namespace == .user }.map(\.id) == [created.entity.id])
        #expect(await backend.store.receipt(for: request(1).id)?.admitted.adapter == first.adapter)
    }

    /// ADR-012 through the intent: a demo collection refuses a new item, and nothing is created.
    @Test func theCreateItemIntentCannotAddToADemoCollection() async throws {
        let backend = try await TestBackend.seeded()
        let intent = CreateItemIntent()
        intent.title = "Graphite stick"
        intent.collection = LabCollectionEntity(try await backend.actions(.appIntent).collection(TestSeed.pigments))
        let error = await #expect(throws: ActionAtlasError.demoCollection) { try await intent.run(with: backend.link) }
        #expect(error?.message.hasPrefix("Demo collections hold only the samples.") == true)
        #expect(await backend.store.items(in: nil).count == 3)
    }

    // MARK: Cancellation

    /// A declined confirmation commits nothing, and the same request can be confirmed later.
    @Test func aDeclinedArchiveCanBeConfirmedLaterUnderTheSameRequest() async throws {
        let backend = try await TestBackend.seeded()
        let intent = ArchiveItemIntent()
        intent.item = try await entity(TestSeed.kraft, in: backend)
        intent.requestID = request(1).id.description
        let spy = ConfirmationSpy()
        await #expect(throws: CancellationError.self) { try await intent.run(with: backend.link, confirm: spy.decline) }
        #expect(backend.commitCount == 0)
        #expect(await backend.store.receipt(for: request(1).id) == nil)

        let confirmed = try await intent.run(with: backend.link, confirm: spy.approve)
        #expect(spy.count == 2, "asked each time")
        #expect(confirmed.value.isArchived && confirmed.value.revision == 2)
        #expect(backend.commitCount == 1)
    }

    /// A task cancelled before its commit changes nothing; the same request then commits once.
    @Test(arguments: AtlasEntryPoint.allCases)
    func aCancelledTaskCanBeRetriedUnderTheSameRequest(entryPoint: AtlasEntryPoint) async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(entryPoint)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await actions.updateItem(TestSeed.cobalt, expected: .initial, title: "Cobalt, dark", note: nil, request: request(1))
        }
        await #expect(throws: ActionAtlasError.cancelled) { try await cancelled.value }
        #expect(await backend.store.receipt(for: request(1).id) == nil)

        let updated = try await actions.updateItem(TestSeed.cobalt, expected: .initial, title: "Cobalt, dark", note: nil, request: request(1))
        #expect(updated.entity.revision.rawValue == 2)
        #expect(backend.commitCount == 1)
    }

    // MARK: Stale state

    /// An entity picked before the app changed the item cannot archive it: the conflict is
    /// recorded, nothing moves, and the app's change stands.
    @Test func aStaleSnapshotCannotArchiveAndRecordsAConflict() async throws {
        let backend = try await TestBackend.seeded()
        let snapshot = try await entity(TestSeed.amber, in: backend)
        _ = try await backend.actions(.appUI).updateItem(TestSeed.amber, expected: .initial, title: "Amber, matte", note: nil, request: request(1))

        let intent = ArchiveItemIntent()
        intent.item = snapshot
        intent.requestID = request(2).id.description
        let error = await #expect(throws: ActionAtlasError.self) {
            try await intent.run(with: backend.link, confirm: ConfirmationSpy().approve)
        }
        guard case .conflict(let conflict)? = error else {
            Issue.record("expected a conflict, got \(String(describing: error))")
            return
        }
        #expect(conflict.expected == .initial && conflict.current.rawValue == 2)
        #expect(await backend.store.receipt(for: request(2).id)?.conflict == conflict, "the conflict receipt is recorded")
        let amber = try await backend.actions(.appUI).item(TestSeed.amber)
        #expect(!amber.isArchived && amber.title.value == "Amber, matte" && amber.revision.rawValue == 2)
    }

    /// An intent's undo offer is pinned to the revision it produced. After the app moved the item
    /// on, using the offer is a conflict, never a revert of the newer change.
    @Test func aStaleUndoOfferIsAConflictNotARevert() async throws {
        let backend = try await TestBackend.seeded()
        let archive = ArchiveItemIntent()
        archive.item = try await entity(TestSeed.cobalt, in: backend)
        let archived = try await archive.run(with: backend.link, confirm: ConfirmationSpy().approve)
        let offer = try #require(archived.receipt?.undo)

        let ui = backend.actions(.appUI)
        _ = try await ui.restoreItem(TestSeed.cobalt, expected: Revision(rawValue: 2)!, request: request(1))
        _ = try await ui.updateItem(TestSeed.cobalt, expected: Revision(rawValue: 3)!, title: "Cobalt, dark", note: nil, request: request(2))

        let stale = try await backend.commit(offer, requestID: request(3).id, authority: .appControl, names: [:])
        #expect(stale.conflict?.expected.rawValue == 2 && stale.conflict?.current.rawValue == 4)
        #expect(stale.changes.isEmpty)
        let cobalt = try await ui.item(TestSeed.cobalt)
        #expect(cobalt.title.value == "Cobalt, dark" && cobalt.revision.rawValue == 4)
    }

    /// Updating from a snapshot taken before the item was archived is refused either way the
    /// snapshot is read: stale, it conflicts; refreshed, it says to restore the item first.
    @Test func anArchivedItemRefusesAnUpdateFromAnySnapshot() async throws {
        let backend = try await TestBackend.seeded()
        let before = try await entity(TestSeed.kraft, in: backend)
        _ = try await backend.actions(.appUI).archiveItem(TestSeed.kraft, expected: .initial, request: request(1), confirm: { _ in })

        let stale = UpdateItemIntent()
        stale.item = before
        stale.newNote = "Brown, stiff, and scored."
        stale.requestID = request(2).id.description
        let staleError = await #expect(throws: ActionAtlasError.self) { try await stale.run(with: backend.link) }
        guard case .conflict? = staleError else {
            Issue.record("expected a conflict, got \(String(describing: staleError))")
            return
        }

        let refreshed = UpdateItemIntent()
        refreshed.item = try await entity(TestSeed.kraft, in: backend)
        refreshed.newNote = "Brown, stiff, and scored."
        refreshed.requestID = request(3).id.description
        let error = await #expect(throws: ActionAtlasError.refused(.ruleViolation(.archived(.item(TestSeed.kraft))))) {
            try await refreshed.run(with: backend.link)
        }
        #expect(error?.message == "It is archived. Restore it before changing it.")
        #expect(try await backend.actions(.appUI).item(TestSeed.kraft).note.value == "Brown and stiff.")
    }

    // MARK: Duplicate state

    /// A late retry of a creation returns the original receipt and leaves later changes in place.
    @Test func aLateRetryOfACreateDoesNotRevertLaterChanges() async throws {
        let backend = try await TestBackend.seeded()
        let notes = try await backend.actions(.appIntent).createCollection(title: "Field notes", request: request(1)).entity
        let create = CreateItemIntent()
        create.title = "Graphite stick"
        create.note = "Soft, 6B."
        create.requestID = request(2).id.description
        let first = try await create.run(with: backend.link)
        _ = try await backend.actions(.appUI).updateItem(
            ItemID(rawValue: first.value.id), expected: .initial, title: nil, note: "Soft, 6B. Smudges.", request: request(3)
        )

        let retry = try await create.run(with: backend.link)
        #expect(retry.receipt == first.receipt)
        #expect(retry.value.id == first.value.id)
        #expect(retry.value.note == "Soft, 6B. Smudges.", "the retry reads the current item, not the original draft")
        #expect(retry.value.revision == 2)
        #expect(await backend.store.items(in: notes.id).count == 1)
    }

    /// Two of the person's collections with the same title are two collections: distinct IDs,
    /// both offered when the system asks which one, and no guess when none is named.
    @Test func sameTitledCollectionsStayDistinctAndMakeTheChoiceAmbiguous() async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(.appIntent)
        let first = try await actions.createCollection(title: "Field notes", request: request(1)).entity
        let second = try await actions.createCollection(title: "Field notes", request: request(2)).entity
        #expect(first.id != second.id)

        let matches = try await CollectionLookup(actions: actions).entities(matching: "field notes", ownOnly: true)
        #expect(Set(matches.map(\.collectionID)) == [first.id, second.id])

        let create = CreateItemIntent()
        create.title = "Graphite stick"
        create.requestID = request(3).id.description
        await #expect(throws: ActionAtlasError.ambiguousCollection(candidates: 2)) { try await create.run(with: backend.link) }
        let chosen = try await create.run(with: backend.link) { candidates in
            try #require(candidates.first { $0.id == second.id })
        }
        #expect(chosen.value.collectionID == second.id.rawValue)
        #expect(await backend.store.items(in: first.id).isEmpty)
    }

    // MARK: Reset Demo and imported user data

    /// Reset Demo restores the samples the intents changed and leaves everything in the user
    /// namespace exactly as it was: the intent's own collection and item, and an item imported
    /// through staging. An import can never land in a demo collection, where a reset could reach it.
    @Test func resetDemoLeavesImportedAndIntentCreatedDataUntouched() async throws {
        let backend = try await TestBackend.seeded()
        let intents = backend.actions(.appIntent)
        let notes = try await intents.createCollection(title: "Field notes", request: request(1)).entity
        let graphite = try await intents.createItem(title: "Graphite stick", note: "Soft, 6B.", in: notes.id, request: request(2)).entity

        // An import, staged and adopted the way the share extension will: data only, into the
        // collection the person chose, under a grant for exactly that new item.
        let inbox = InMemoryStagingInbox()
        let staged = await inbox.stage(try StagingRecord.text(utf8: Array("Harbor walk\nBring the blue notebook.".utf8)))
        try backend.ledger.issue(to: .shareExtension, for: [.createItem], on: ImportAdopter.grantTarget(into: notes.id))
        let adopter = ImportAdopter(service: backend.service, inbox: inbox, ledger: backend.ledger)
        let imported = try await adopter.adopt(staged.id, into: notes.id)
        let importedID = try #require(imported.receipt.changes.first?.entity)

        // An import cannot go into a demo collection.
        let demoStaged = await inbox.stage(try StagingRecord.text(utf8: Array("Tide table".utf8)))
        try backend.ledger.issue(to: .shareExtension, for: [.createItem], on: ImportAdopter.grantTarget(into: TestSeed.pigments))
        await #expect(throws: ImportRejection.destinationUnavailable) { try await adopter.adopt(demoStaged.id, into: TestSeed.pigments) }

        // The intents change two samples.
        _ = try await intents.updateItem(TestSeed.amber, expected: .initial, title: "Amber, matte", note: nil, request: request(3))
        let archived = try await intents.archiveItem(TestSeed.cobalt, expected: .initial, request: request(4), confirm: ConfirmationSpy().approve)
        let userBefore = await userState(backend)
        #expect(userBefore.collections.map(\.id) == [notes.id])
        #expect(userBefore.items.count == 2 && userBefore.items.contains { $0.id == graphite.id })

        // Reset Demo, as the person confirms it in the app.
        let reset = try await backend.commit(.resetDemo(seed: TestSeed.seed), requestID: request(5).id, authority: .appControl, names: [:])
        #expect(reset.conflict == nil)
        #expect(Set(reset.changes.map(\.entity)) == [.item(TestSeed.amber), .item(TestSeed.cobalt)])
        #expect(reset.removed.isEmpty)

        // The user namespace is byte-for-byte what it was, and its receipts are still recorded.
        let userAfter = await userState(backend)
        #expect(userAfter.collections == userBefore.collections)
        #expect(userAfter.items == userBefore.items)
        #expect(await backend.store.receipt(for: imported.receipt.requestID) == imported.receipt)
        #expect(await backend.store.receipt(for: request(2).id)?.changes.map(\.entity) == [.item(graphite.id)])
        #expect(importedID != .item(graphite.id))

        // The samples are back at their next revision, and the intent's old undo offer is stale.
        let amber = try await intents.item(TestSeed.amber)
        let cobalt = try await intents.item(TestSeed.cobalt)
        #expect(amber.title.value == "Amber swatch" && amber.revision.rawValue == 3)
        #expect(!cobalt.isArchived && cobalt.revision.rawValue == 3)
        let staleUndo = try await backend.commit(try #require(archived.receipt.undo), requestID: request(6).id, authority: .appControl, names: [:])
        #expect(staleUndo.conflict != nil)
    }

    // MARK: Helpers

    private func entity(_ id: ItemID, in backend: TestBackend) async throws -> LabItemEntity {
        try #require(try await ItemLookup(actions: backend.actions(.appIntent)).entities(for: [id]).first)
    }

    private func userState(_ backend: TestBackend) async -> (collections: [LabCollection], items: [LabItem]) {
        let state = await backend.snapshot()
        return (state.collections.filter { $0.namespace == .user }, state.items.filter { $0.namespace == .user })
    }
}
