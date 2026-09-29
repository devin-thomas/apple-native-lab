@testable import ActionAtlas
import Foundation
import LabDomain
import Testing

/// LAB-001: each Action Atlas action, through the operation service, from both entry points.
@Suite struct ActionAtlasOperationTests {
    @Test(arguments: AtlasEntryPoint.allCases)
    func createCollectionMakesOneOfYourOwn(entryPoint: AtlasEntryPoint) async throws {
        let backend = try await TestBackend.seeded()
        let outcome = try await backend.actions(entryPoint).createCollection(title: "  Field notes ", request: request(1))

        #expect(outcome.entity.title.value == "Field notes")
        #expect(outcome.entity.namespace == .user)
        #expect(outcome.entity.revision == .initial)
        #expect(outcome.entity.id == request(1).newCollectionID)
        #expect(outcome.receipt.admitted.adapter == entryPoint.adapter)
        #expect(outcome.receipt.summary == "Created collection “Field notes”.")
        #expect(outcome.receipt.undo == .archiveCollection(id: outcome.entity.id, expected: .initial))
    }

    @Test(arguments: AtlasEntryPoint.allCases)
    func createItemGoesIntoYourOnlyCollection(entryPoint: AtlasEntryPoint) async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(entryPoint)
        let notes = try await actions.createCollection(title: "Field notes", request: request(1)).entity

        let outcome = try await actions.createItem(title: "Graphite stick", note: "Soft, 6B.", in: nil, request: request(2))
        #expect(outcome.entity.collectionID == notes.id)
        #expect(outcome.entity.namespace == .user)
        #expect(outcome.entity.note.value == "Soft, 6B.")
        #expect(outcome.entity.id == request(2).newItemID)
        #expect(outcome.receipt.summary == "Created item “Graphite stick” in “Field notes”.")
    }

    @Test func findItemsUsesTheDomainMatchingRules() async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(.appIntent)

        #expect(try await actions.findItems(text: "SWATCH").map(\.title.value) == ["Amber swatch", "Cobalt swatch"])
        #expect(try await actions.findItems(text: "brown").map(\.title.value) == ["Amber swatch", "Kraft card"])
        #expect(try await actions.findItems(in: TestSeed.papers).map(\.id) == [TestSeed.kraft])
        #expect(try await actions.findItems(limit: 1).count == 1)
        #expect(try await actions.findItems(text: "nothing like this").isEmpty)
    }

    @Test func getItemReadsTheCurrentState() async throws {
        let backend = try await TestBackend.seeded()
        let item = try await backend.actions(.appIntent).item(TestSeed.amber)
        #expect(item.title.value == "Amber swatch")
        #expect(item.namespace == .demo)
        #expect(item.revision == .initial)
    }

    @Test(arguments: AtlasEntryPoint.allCases)
    func updateItemChangesADemoSampleAtTheRevisionSeen(entryPoint: AtlasEntryPoint) async throws {
        let backend = try await TestBackend.seeded()
        let outcome = try await backend.actions(entryPoint).updateItem(
            TestSeed.amber, expected: .initial, title: "Amber swatch, matte", note: nil, request: request(1)
        )
        #expect(outcome.entity.title.value == "Amber swatch, matte")
        #expect(outcome.entity.note.value == "Warm yellow-brown.")
        #expect(outcome.entity.revision.rawValue == 2)
        #expect(outcome.entity.namespace == .demo, "an edited sample stays in the demo, so Reset Demo can restore it")
        #expect(outcome.receipt.undo == .updateItem(
            id: TestSeed.amber, expected: outcome.entity.revision, changes: try ItemChanges(title: EntityTitle("Amber swatch"))
        ))
    }

    @Test func archiveFromAnIntentAsksOnceThenCommitsWithAnUndo() async throws {
        let backend = try await TestBackend.seeded()
        let spy = ConfirmationSpy()
        let outcome = try await backend.actions(.appIntent).archiveItem(
            TestSeed.cobalt, expected: .initial, request: request(1), confirm: spy.approve
        )

        #expect(spy.count == 1)
        #expect(spy.prompts.withLock { $0.first?.text.hasPrefix("Archive “Cobalt swatch”?") } == true)
        #expect(outcome.entity.isArchived)
        #expect(outcome.receipt.admitted.adapter == .appIntent)
        #expect(outcome.receipt.undo == .restoreItem(id: TestSeed.cobalt, expected: outcome.entity.revision))
        // The one commit carried the confirmation of exactly this archive, and nothing else.
        let authorities = backend.commits.withLock { $0.map(\.1) }
        #expect(authorities == [.intent(IntentConfirmation(confirmed: .archiveItem(id: TestSeed.cobalt, expected: .initial)))])
    }

    @Test func archiveFromTheAppIsAControlPress() async throws {
        let backend = try await TestBackend.seeded()
        let outcome = try await backend.actions(.appUI).archiveItem(
            TestSeed.cobalt, expected: .initial, request: request(1), confirm: { _ in }
        )
        #expect(outcome.entity.isArchived)
        #expect(backend.commits.withLock { $0.map(\.1) } == [.appControl])
    }

    @Test(arguments: AtlasEntryPoint.allCases)
    func restoreItemReturnsAnArchivedItem(entryPoint: AtlasEntryPoint) async throws {
        let backend = try await TestBackend.seeded()
        let actions = backend.actions(entryPoint)
        let archived = try await actions.archiveItem(TestSeed.kraft, expected: .initial, request: request(1), confirm: { _ in })
        let restored = try await actions.restoreItem(TestSeed.kraft, expected: archived.entity.revision, request: request(2))
        #expect(!restored.entity.isArchived)
        #expect(restored.entity.revision.rawValue == 3)
        #expect(restored.receipt.undo == .archiveItem(id: TestSeed.kraft, expected: restored.entity.revision))
    }

    @Test func exportIsAPortableDocumentAboutOneItem() async throws {
        let backend = try await TestBackend.seeded()
        let export = try await backend.actions(.appIntent).exportItem(TestSeed.amber, as: .json)

        #expect(export.filename == "Amber swatch.json")
        let document = try JSONDecoder().decode(PortableLabItem.self, from: export.data)
        #expect(document == export.document)
        #expect(document.format == "native-lab-item")
        #expect(document.formatVersion == 1)
        #expect(document.id == TestSeed.amber.rawValue)
        #expect(document.title == "Amber swatch")
        #expect(document.note == "Warm yellow-brown.")
        #expect(document.collection == .init(id: TestSeed.pigments.rawValue, title: "Pigment swatches"))
        #expect(document.demoSample)
        // Exactly the documented fields: no receipts, request IDs, other items, or store metadata.
        let keys = try #require(JSONSerialization.jsonObject(with: export.data) as? [String: Any]).keys
        #expect(Set(keys) == ["format", "formatVersion", "id", "title", "note", "archived", "revision", "demoSample", "collection"])
        // Stable bytes: the same state exports identically.
        #expect(try await backend.actions(.appUI).exportItem(TestSeed.amber, as: .json).data == export.data)
        #expect(await backend.store.receipt(for: request(1).id) == nil)
        #expect(backend.commitCount == 0, "export is read-only")
    }

    @Test func plainTextExportReadsLikeANote() async throws {
        let backend = try await TestBackend.seeded()
        let export = try await backend.actions(.appIntent).exportItem(TestSeed.kraft, as: .plainText)
        #expect(export.filename == "Kraft card.txt")
        #expect(export.text.hasPrefix("Kraft card\n\nBrown and stiff.\n\nCollection: Paper stock\nStatus: Active\nRevision: 1\n"))
    }

    @Test func exportFileNamesCannotEscapeTheirFolder() {
        #expect(AtlasExport.safeName("../../etc/passwd") == "-..-etc-passwd")
        #expect(AtlasExport.safeName("...") == "Lab item")
        #expect(AtlasExport.safeName("a:b\\c") == "a-b-c")
        #expect(AtlasExport.safeName(String(repeating: "x", count: 100)).count == 60)
    }
}
