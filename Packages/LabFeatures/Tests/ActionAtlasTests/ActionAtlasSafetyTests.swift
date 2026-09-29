@testable import ActionAtlas
import Foundation
import LabDomain
import Testing

/// LAB-001: duplicates, cancellation, invalid input, missing and ambiguous entities, grants, and
/// the unavailable path. Every refusal changes nothing and says so in a readable sentence.
@Suite struct ActionAtlasSafetyTests {
    // MARK: Idempotency

    @Test(arguments: AtlasEntryPoint.allCases)
    func aDuplicateRequestIDCommitsOnce(entryPoint: AtlasEntryPoint) async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(entryPoint)
        let first = try await actions.createCollection(title: "Field notes", request: request(1))
        let retry = try await actions.createCollection(title: "Field notes", request: request(1))

        #expect(retry.receipt == first.receipt, "a retry returns the recorded receipt")
        #expect(await backend.store.collections().count(where: { $0.namespace == .user }) == 1)

        let item = try await actions.createItem(title: "Graphite stick", in: first.entity.id, request: request(2))
        let itemRetry = try await actions.createItem(title: "Graphite stick", in: first.entity.id, request: request(2))
        #expect(itemRetry.receipt == item.receipt)
        #expect(await backend.store.items(in: first.entity.id).count == 1)

        let archive = try await actions.archiveItem(item.entity.id, expected: .initial, request: request(3), confirm: { _ in })
        let archiveRetry = try await actions.archiveItem(item.entity.id, expected: .initial, request: request(3), confirm: { _ in })
        #expect(archiveRetry.receipt == archive.receipt)
        #expect(try await actions.item(item.entity.id).revision.rawValue == 2, "archived once, not twice")
    }

    @Test func aRequestIDUsedForAnotherChangeIsRefused() async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(.appIntent)
        _ = try await actions.createCollection(title: "Field notes", request: request(1))

        let error = await #expect(throws: ActionAtlasError.self) {
            try await actions.updateItem(TestSeed.amber, expected: .initial, title: "Other", note: nil, request: request(1))
        }
        #expect(error == .refused(.requestIDReused(request(1).id)))
        #expect(error?.message.contains("already used") == true)
        #expect(try await actions.item(TestSeed.amber).revision == .initial)
    }

    @Test func aShortcutsRequestIDIsParsedAndDerivesStableEntityIDs() throws {
        let text = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
        let parsed = try AtlasRequest(text: "  \(text.lowercased()) ")
        #expect(parsed.id.rawValue.uuidString == text)
        #expect(try AtlasRequest(text: text).newCollectionID == parsed.newCollectionID)
        #expect(parsed.newCollectionID.rawValue != parsed.newItemID.rawValue)
        #expect(parsed.newCollectionID.rawValue != parsed.id.rawValue)
        // The derived IDs keep a valid version and variant.
        #expect(parsed.newItemID.rawValue.uuidString.dropFirst(14).first == "4")
        #expect(try AtlasRequest(text: nil).id != AtlasRequest(text: "").id, "no text means a new request each time")
        #expect(throws: ActionAtlasError.invalidRequestID) { try AtlasRequest(text: "not-a-uuid") }
    }

    // MARK: Cancellation

    @Test func decliningTheConfirmationCommitsNothing() async throws {
        let backend = try await TestBackend.seeded()
        let spy = ConfirmationSpy()
        await #expect(throws: CancellationError.self) {
            try await backend.actions(.appIntent).archiveItem(
                TestSeed.amber, expected: .initial, request: request(1), confirm: spy.decline
            )
        }
        #expect(spy.count == 1)
        #expect(backend.commitCount == 0)
        #expect(await backend.store.receipt(for: request(1).id) == nil)
        #expect(await backend.store.item(TestSeed.amber)?.isArchived == false)
    }

    @Test func aCancelledTaskStopsBeforeTheCommit() async throws {
        let backend = try await TestBackend.seeded()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await backend.actions(.appIntent).createCollection(title: "Field notes", request: request(1))
        }
        await #expect(throws: ActionAtlasError.cancelled) { try await task.value }
        #expect(backend.commitCount == 0)
        #expect(await backend.store.collections().count == 2)
        #expect(ActionAtlasError.cancelled.message == "Cancelled. Nothing was changed.")
    }

    @Test func decliningToChooseACollectionCommitsNothing() async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(.appIntent)
        _ = try await actions.createCollection(title: "Field notes", request: request(1))
        _ = try await actions.createCollection(title: "Glazes", request: request(2))
        await #expect(throws: CancellationError.self) {
            try await actions.createItem(title: "Graphite stick", in: nil, request: request(3)) { _ in throw CancellationError() }
        }
        #expect(await backend.store.receipt(for: request(3).id) == nil)
    }

    // MARK: Invalid input

    @Test(arguments: [
        ("", ValidationError.emptyTitle),
        ("   ", .emptyTitle),
        (String(repeating: "x", count: 121), .titleTooLong(limit: 120)),
        ("Line\nbreak", .controlCharacter(in: .title)),
    ])
    func anInvalidTitleChangesNothing(title: String, reason: ValidationError) async throws {
        let backend = try await TestBackend.seeded()
        await #expect(throws: ActionAtlasError.invalidInput(reason)) {
            try await backend.actions(.appIntent).createCollection(title: title, request: request(1))
        }
        #expect(backend.commitCount == 0)
        #expect(!ActionAtlasError.invalidInput(reason).message.isEmpty)
    }

    @Test func otherInvalidInputChangesNothing() async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(.appIntent)
        _ = try await actions.createCollection(title: "Field notes", request: request(1))

        await #expect(throws: ActionAtlasError.invalidInput(.noteTooLong(limit: 2_000))) {
            try await actions.createItem(title: "Long", note: String(repeating: "n", count: 2_001), in: nil, request: request(2))
        }
        await #expect(throws: ActionAtlasError.invalidInput(.emptyChanges)) {
            try await actions.updateItem(TestSeed.amber, expected: .initial, title: nil, note: nil, request: request(3))
        }
        await #expect(throws: ActionAtlasError.refused(.ruleViolation(.noChanges(.item(TestSeed.amber))))) {
            try await actions.updateItem(TestSeed.amber, expected: .initial, title: "Amber swatch", note: nil, request: request(4))
        }
        await #expect(throws: ActionAtlasError.invalidInput(.resultLimitOutOfRange(allowed: 1...200))) {
            try await actions.findItems(limit: 0)
        }
        await #expect(throws: ActionAtlasError.invalidInput(.controlCharacter(in: .searchText))) {
            try await actions.findItems(text: "bell\u{0007}")
        }
        #expect(backend.commitCount == 2, "only the collection and the refused no-op update reached the service")
        #expect(await backend.store.items(in: nil).count == 3)
    }

    @Test func aStaleRevisionRecordsAConflictAndOverwritesNothing() async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(.appIntent)
        _ = try await actions.updateItem(TestSeed.amber, expected: .initial, title: "Amber, matte", note: nil, request: request(1))

        let error = await #expect(throws: ActionAtlasError.self) {
            try await actions.updateItem(TestSeed.amber, expected: .initial, title: "Amber, gloss", note: nil, request: request(2))
        }
        guard case .conflict(let conflict)? = error else {
            Issue.record("expected a conflict, got \(String(describing: error))")
            return
        }
        #expect(conflict.entity == .item(TestSeed.amber))
        #expect(conflict.expected == .initial)
        #expect(conflict.current.rawValue == 2)
        #expect(error?.message.hasPrefix("Not applied: the item changed after it was picked (expected revision 1, found 2).") == true)
        #expect(await backend.store.receipt(for: request(2).id)?.conflict == conflict, "the conflict receipt is recorded")
        #expect(try await actions.item(TestSeed.amber).title.value == "Amber, matte")
    }

    // MARK: Missing and ambiguous

    @Test func aMissingItemIsARecoverableError() async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(.appIntent)
        let gone = ItemID()
        await #expect(throws: ActionAtlasError.missingItem(gone)) { try await actions.item(gone) }
        await #expect(throws: ActionAtlasError.missingItem(gone)) {
            try await actions.archiveItem(gone, expected: .initial, request: request(1), confirm: { _ in })
        }
        await #expect(throws: ActionAtlasError.missingItem(gone)) { try await actions.exportItem(gone, as: .json) }
        #expect(ActionAtlasError.missingItem(gone).message.hasPrefix("That lab item no longer exists. Find it again"))
        // An entity query leaves a missing identifier out instead of failing the whole lookup.
        #expect(try await actions.items(ids: [gone, TestSeed.kraft]).map(\.id) == [TestSeed.kraft])
        #expect(backend.commitCount == 0)
    }

    @Test func aMissingCollectionIsARecoverableError() async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(.appIntent)
        let gone = CollectionID()
        await #expect(throws: ActionAtlasError.missingCollection(gone)) { try await actions.findItems(in: gone) }
        await #expect(throws: ActionAtlasError.missingCollection(gone)) {
            try await actions.createItem(title: "Orphan", in: gone, request: request(1))
        }
        #expect(try await actions.collections(ids: [gone, TestSeed.papers]).map(\.id) == [TestSeed.papers])
    }

    @Test func aNewItemNeedsACollectionOfYourOwn() async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(.appIntent)
        await #expect(throws: ActionAtlasError.noCollectionOfYourOwn) {
            try await actions.createItem(title: "Graphite stick", in: nil, request: request(1))
        }
        // ADR-012: a demo collection holds only the samples.
        let error = await #expect(throws: ActionAtlasError.demoCollection) {
            try await actions.createItem(title: "Graphite stick", in: TestSeed.pigments, request: request(2))
        }
        #expect(error?.message.hasPrefix("Demo collections hold only the samples.") == true)
        #expect(await backend.store.items(in: TestSeed.pigments).count == 2)
    }

    @Test func severalCollectionsOfYourOwnAreAmbiguousUntilOneIsChosen() async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(.appIntent)
        _ = try await actions.createCollection(title: "Field notes", request: request(1))
        let glazes = try await actions.createCollection(title: "Glazes", request: request(2)).entity

        let error = await #expect(throws: ActionAtlasError.ambiguousCollection(candidates: 2)) {
            try await actions.createItem(title: "Celadon tile", in: nil, request: request(3))
        }
        #expect(error?.message == "2 of your collections could hold the item. Choose one. Nothing was changed.")

        let offered = OfferedChoices()
        let chosen = try await actions.createItem(title: "Celadon tile", in: nil, request: request(3)) { candidates in
            await offered.record(candidates.map(\.title.value))
            return try #require(candidates.first { $0.title.value == "Glazes" })
        }
        #expect(await offered.titles == ["Field notes", "Glazes"], "only your own collections are offered, by title")
        #expect(chosen.entity.collectionID == glazes.id)
    }

    @Test func textThatMatchesSeveralItemsReturnsThemAllForTheSystemToDisambiguate() async throws {
        let backend = try await TestBackend.seeded()
        let lookup = ItemLookup(actions: backend.actions(.appIntent))
        let matches = try await lookup.entities(matching: "swatch")
        #expect(matches.map(\.title) == ["Amber swatch", "Cobalt swatch"])
        #expect(matches.allSatisfy { $0.collectionTitle == "Pigment swatches" && $0.isDemoSample })
        #expect(try await lookup.entities(matching: "zzz").isEmpty)
        #expect(try await lookup.entities(for: [ItemID(), TestSeed.amber]).map(\.title) == ["Amber swatch"])
    }

    // MARK: Grants (ADR-013)

    @Test func anIntentCannotArchiveWithoutTheConfirmation() async throws {
        let backend = try await TestBackend.seeded()
        let archive = DomainOperation.archiveItem(id: TestSeed.amber, expected: .initial)

        let error = await #expect(throws: ActionAtlasError.self) {
            try await backend.commit(archive, requestID: request(1).id, authority: .intent(nil), names: [:])
        }
        guard case .refused(.unauthorized(let denial))? = error else {
            Issue.record("expected a refusal, got \(String(describing: error))")
            return
        }
        #expect(denial.adapter == .appIntent)
        #expect(denial.required == .commitDestructive)
        #expect(denial.reason == .deniedByPolicy, "the grant policy refused: no grant without the confirmation")
        #expect(error?.message == "Archiving from Shortcuts or Siri needs your confirmation, and none was given. Nothing was changed.")
        #expect(await backend.store.receipt(for: request(1).id) == nil)
        #expect(await backend.store.item(TestSeed.amber)?.isArchived == false)
    }

    @Test func aConfirmationCoversOnlyTheChangeThatWasConfirmed() async throws {
        let backend = try await TestBackend.seeded()
        let confirmed = IntentConfirmation(confirmed: .archiveItem(id: TestSeed.cobalt, expected: .initial))
        await #expect(throws: ActionAtlasError.self) {
            try await backend.commit(
                .archiveItem(id: TestSeed.amber, expected: .initial), requestID: request(1).id,
                authority: .intent(confirmed), names: [:]
            )
        }
        #expect(await backend.store.item(TestSeed.amber)?.isArchived == false)
    }

    @Test func nonDestructiveIntentChangesNeedNoGrant() async throws {
        let backend = try await TestBackend.seeded()
        _ = try await backend.actions(.appIntent).createCollection(title: "Field notes", request: request(1))
        #expect(backend.commits.withLock { $0.map(\.1) } == [.intent(nil)])
        #expect(backend.ledger.liveGrants.isEmpty)
    }

    // MARK: Unavailable

    @Test func withoutAConnectedStoreEveryActionSaysWhy() async throws {
        let actions = ActionAtlasLink.unavailable.actions(.appIntent)
        let reason = "Native Lab has not opened its store for actions yet. Open Native Lab and try again."
        await #expect(throws: ActionAtlasError.unavailable(reason: reason)) {
            try await actions.createCollection(title: "Field notes", request: request(1))
        }
        await #expect(throws: ActionAtlasError.unavailable(reason: reason)) { try await actions.findItems() }
        await #expect(throws: ActionAtlasError.unavailable(reason: reason)) { try await actions.item(TestSeed.amber) }
        await #expect(throws: ActionAtlasError.unavailable(reason: reason)) { try await actions.collections() }
        await #expect(throws: ActionAtlasError.unavailable(reason: reason)) { try await actions.exportItem(TestSeed.amber, as: .json) }
        let spy = ConfirmationSpy()
        await #expect(throws: ActionAtlasError.unavailable(reason: reason)) {
            try await actions.archiveItem(TestSeed.amber, expected: .initial, request: request(2), confirm: spy.approve)
        }
        #expect(spy.count == 0, "nothing is asked when nothing can be done")
        #expect(ActionAtlasError.unavailable(reason: reason).message == reason)
    }

    @Test func everyErrorHasAReadableSentence() throws {
        let conflict = try JSONDecoder().decode(RevisionConflict.self, from: Data("""
            {"entity": {"kind": "item", "id": "\(UUID().uuidString)"}, "expected": 1, "current": 4}
            """.utf8))
        let errors: [ActionAtlasError] = [
            .unavailable(reason: "The store is closed."), .invalidInput(.emptyTitle), .invalidRequestID,
            .missingItem(ItemID()), .missingCollection(CollectionID()), .noCollectionOfYourOwn,
            .ambiguousCollection(candidates: 3), .demoCollection,
            .conflict(conflict),
            .refused(.storeFailure(.contention)), .refused(.requestIDReused(RequestID())), .cancelled,
        ]
        for error in errors {
            #expect(!error.message.isEmpty)
            #expect(error.errorDescription == error.message)
            #expect(error.message.hasSuffix(".") || error.message.hasSuffix("app."), "a full sentence: \(error.message)")
            #expect(!error.message.contains("SQL"))
        }
    }
}

private actor OfferedChoices {
    private(set) var titles: [String] = []

    func record(_ titles: [String]) { self.titles = titles }
}
