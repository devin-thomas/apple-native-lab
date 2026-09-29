import ActionAtlas
import AppIntents
import Foundation
import LabDomain
import Testing

/// LAB-001: the App Intents themselves, run without the system through `run(with:)`, the call
/// their `perform()` makes after adding the system's dialogs. This proves the adapter code and its
/// typed output; it is not proof of a Shortcuts or Siri run (docs/SHORTCUTS_AND_INTENTS.md).
@Suite struct ActionAtlasIntentTests {
    @Test func theIntentsCreateFindUpdateArchiveRestoreAndExport() async throws {
        let backend = try await TestBackend.seeded()
        let link = backend.link

        let createCollection = CreateCollectionIntent()
        createCollection.title = "Field notes"
        let collection = try await createCollection.run(with: link)
        #expect(collection.value.title == "Field notes")
        #expect(!collection.value.isDemo)
        #expect(collection.dialog == "Created collection “Field notes”. Its receipt in Native Lab offers an undo.")
        #expect(collection.receipt?.admitted.adapter == .appIntent)

        let createItem = CreateItemIntent()
        createItem.title = "Graphite stick"
        createItem.note = "Soft, 6B."
        let created = try await createItem.run(with: link)
        #expect(created.value.collectionTitle == "Field notes")
        #expect(created.value.revision == 1)
        #expect(!created.value.isDemoSample)

        let find = FindItemsIntent()
        find.text = "graphite"
        find.includeArchived = false
        find.limit = 20
        let found = try await find.run(with: link)
        #expect(found.value.map(\.id) == [created.value.id])
        #expect(found.dialog == "Found 1 lab item.")

        let update = UpdateItemIntent()
        update.item = found.value[0]
        update.newNote = "Soft, 6B. Smudges easily."
        let updated = try await update.run(with: link)
        #expect(updated.value.note == "Soft, 6B. Smudges easily.")
        #expect(updated.value.revision == 2)

        let archive = ArchiveItemIntent()
        archive.item = updated.value
        let spy = ConfirmationSpy()
        let archived = try await archive.run(with: link, confirm: spy.approve)
        #expect(spy.count == 1)
        #expect(archived.value.isArchived)
        #expect(archived.receipt?.undo == .restoreItem(id: ItemID(rawValue: archived.value.id), expected: Revision(rawValue: 3)!))

        let restore = RestoreItemIntent()
        restore.item = archived.value
        let restored = try await restore.run(with: link)
        #expect(!restored.value.isArchived)

        let get = GetItemIntent()
        get.item = restored.value
        let current = try await get.run(with: link)
        #expect(current.value.revision == 4)
        #expect(current.dialog == "“Graphite stick” is at revision 4.")

        let export = ExportItemIntent()
        export.item = current.value
        export.format = .json
        let exported = try await export.run(with: link)
        #expect(exported.value.document.revision == 4)
        #expect(exported.value.filename == "Graphite stick.json")
        #expect(exported.dialog == "Exported “Graphite stick” as JSON.")
    }

    @Test func createItemAsksWhichCollectionWhenYouHaveSeveral() async throws {
        let backend = try await TestBackend.seeded()
        for (index, title) in ["Field notes", "Glazes"].enumerated() {
            let intent = CreateCollectionIntent()
            intent.title = title
            intent.requestID = request(index + 1).id.description
            _ = try await intent.run(with: backend.link)
        }
        let createItem = CreateItemIntent()
        createItem.title = "Celadon tile"
        await #expect(throws: ActionAtlasError.ambiguousCollection(candidates: 2)) {
            try await createItem.run(with: backend.link)
        }
        let created = try await createItem.run(with: backend.link) { candidates in
            try #require(candidates.last)
        }
        #expect(created.value.collectionTitle == "Glazes")
    }

    @Test func aStoredItemThatNoLongerExistsFailsReadably() async throws {
        let backend = try await TestBackend.seeded()
        let item = try await backend.actions(.appIntent).item(TestSeed.kraft)
        let ghost = LabItemEntity(
            LabItem(id: ItemID(), collectionID: item.collectionID, title: item.title, revision: item.revision, namespace: .demo),
            collectionTitle: "Paper stock"
        )
        let get = GetItemIntent()
        get.item = ghost
        let error = await #expect(throws: ActionAtlasError.self) { try await get.run(with: backend.link) }
        #expect(error == .missingItem(ghost.itemID))
    }

    @Test func aRequestIDMakesAnIntentRetrySafe() async throws {
        let backend = try await TestBackend.seeded()
        let intent = CreateCollectionIntent()
        intent.title = "Field notes"
        intent.requestID = request(7).id.description
        let first = try await intent.run(with: backend.link)
        let second = try await intent.run(with: backend.link)
        #expect(first.value.id == second.value.id)
        #expect(first.receipt == second.receipt)
        #expect(await backend.store.collections().count(where: { $0.namespace == .user }) == 1)

        intent.requestID = "yesterday"
        await #expect(throws: ActionAtlasError.invalidRequestID) { try await intent.run(with: backend.link) }
    }

    @Test func intentsWithoutAHostAreUnavailable() async throws {
        let find = FindItemsIntent()
        find.text = nil
        find.includeArchived = false
        find.limit = 20
        await #expect(throws: ActionAtlasError.self) { try await find.run(with: .unavailable) }
    }

    @Test func entitiesShowWhatTheyAre() async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(.appIntent)
        let amber = try await actions.item(TestSeed.amber)
        let entity = LabItemEntity(amber, collectionTitle: "Pigment swatches")
        #expect(entity.subtitle == "Pigment swatches · Demo sample")
        #expect(entity.itemID == TestSeed.amber)
        let collection = LabCollectionEntity(try await actions.collection(TestSeed.papers))
        #expect(collection.subtitle == "Demo · samples only")
    }
}
