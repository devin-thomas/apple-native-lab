import CryptoKit
import Foundation
import LabDomain
import LabSupport
import ShortcutWorkbench
import Testing
@testable import NativeLab

/// Fresh SQLite state through the host backend and model. No Shortcuts process participates.
@MainActor
@Suite struct ShortcutWorkbenchQualificationHostTests {
    @Test func boundRecipeRunsAfterRenameAndResetPreservesUserImport() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShortcutWorkbenchQualification-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        let backend = LibraryWorkbenchBackend(library: library)
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let actions = WorkbenchActions(backend: backend, entryPoint: .appUI, catalog: catalog)
        let collection = CollectionID(rawValue: UUID(uuidString: "A3C00300-0003-4000-8000-000000000001")!)
        _ = try await library.submit(
            .createCollection(draft: CollectionDraft(id: collection, title: EntityTitle("Qualification inbox"))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        let staging = RecipeImportStaging()
        let request = WorkbenchRequest(RequestID(rawValue: UUID(uuidString: "A3C00300-0003-4000-8000-000000000002")!))
        let draft = try await actions.beginImport(title: "Original workbench sample", note: "Original neutral text.", into: collection, staging: staging)
        let imported = try await actions.commitImport(draft, into: collection, request: request, staging: staging)
        var recipe = RecipeDefinition.importExportWalkthrough(sourceItemIDs: [imported.entity.id])
        recipe.steps.removeAll { $0.kind == .importDocument }
        actions.saveRecipe(recipe)
        let input = RecipeExport(recipe: recipe).data
        _ = try await library.submit(
            .updateItem(id: imported.entity.id, expected: imported.entity.revision, changes: ItemChanges(title: EntityTitle("Renamed workbench sample"))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        let result = try await actions.runRecipe(recipe, into: nil, request: WorkbenchRequest(), staging: staging)
        #expect(result.job.state == .completed)
        #expect(result.matched.first?.title.value == "Renamed workbench sample")
        #expect(result.matched.first?.note.value == "Original neutral text. · recipe transform")
        #expect(result.export?.recipe.sourceItemIDs == [imported.entity.id])
        #expect(result.transformReceipt?.admitted.adapter == .appUI)
        let current = try await actions.resolveItem(imported.entity.id)
        #expect(await library.resetDemo() != nil)
        #expect(try await actions.resolveItem(imported.entity.id) == current)
        #expect(catalog.recipe(recipe.id) == recipe)

        let cancelled = try await actions.beginImport(title: "Cancelled original sample", into: collection, staging: staging)
        await actions.cancelImport(cancelled, staging: staging)
        await #expect(throws: WorkbenchError.self) {
            try await actions.commitImport(cancelled, into: collection, request: WorkbenchRequest(), staging: staging)
        }
        #expect(await staging.pendingCount == 0)

        let model = ShortcutWorkbenchModel()
        model.connect(library)
        model.export(recipe)
        #expect(model.lastExportText == RecipeExport(recipe: recipe).text)
        let record = try EvidenceRecord(
            subject: "LAB-003",
            check: "Host backend: staged import, stable-ID rename, bound query-transform-export, cancellation and Reset Demo",
            date: Date(), provenance: .current, execution: .fixture,
            inputs: ["bound-original-recipe@sha256:" + SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()],
            steps: [
                "Run ShortcutWorkbenchQualificationHostTests in the built host test action",
                "Open a fresh SQLite store; create Qualification inbox; stage and commit Original workbench sample",
                "Bind the imported ID to query-transform-export; rename through LabLibrary.submit; run through LibraryWorkbenchBackend",
                "Reset Demo and compare the imported user item and session catalog; cancel a second staged import",
                "Connect a fresh ShortcutWorkbenchModel and compare its export text"
            ],
            outcome: .passed(observed: "The bound recipe completed after rename with one appUI transform receipt; export retained the stable ID. Reset left the user item and session recipe unchanged. Cancellation removed the draft and refused commit. Host model export matched RecipeExport."),
            limitations: [
                "Fixture invocation inside the host, not a Shortcuts, Siri, Storage or model execution. No UI controls or assistive technology were driven.",
                "The fresh unbound four-step recipe is recorded separately by freshRecipeCompletesInOneCommitAndExportWithholdsTypedText.",
                "No physical mobile device, cross-device identity or durable recipe persistence was tested. Export hash identifies an original recipe with no credentials."
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        Attachment.record(String(decoding: try encoder.encode(record), as: UTF8.self), named: "LAB-003-host-bound-recipe.json")
        #expect(record.provenance.xcodeBuild != "unknown")
    }

    @Test func freshRecipeCompletesInOneCommitAndExportWithholdsTypedText() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShortcutWorkbenchFresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        let backend = LibraryWorkbenchBackend(library: library)
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let actions = WorkbenchActions(backend: backend, entryPoint: .appUI, catalog: catalog)
        let collection = CollectionID(rawValue: UUID(uuidString: "A3C00300-0003-4000-8000-000000000011")!)
        _ = try await library.submit(
            .createCollection(draft: CollectionDraft(id: collection, title: EntityTitle("Qualification inbox"))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        let inbox = try ItemFilter(collectionID: collection, includeArchived: true, limit: 200)
        let staging = RecipeImportStaging()

        // An unrunnable recipe is refused before anything is staged or committed.
        let unbound = RecipeDefinition(title: "Original unbound transform", steps: [
            RecipeStep(order: 1, kind: .transform, detail: " · recipe transform"), RecipeStep(order: 2, kind: .export),
        ])
        await #expect(throws: WorkbenchError.self) {
            try await actions.runRecipe(unbound, into: collection, request: WorkbenchRequest(), staging: staging)
        }
        #expect(try await backend.items(inbox, via: .appUI).isEmpty)
        #expect(await staging.pendingCount == 0)

        // The fresh four-step walkthrough binds what it imports and completes in one commit.
        let recipe = RecipeDefinition.importExportWalkthrough()
        let request = WorkbenchRequest(RequestID(rawValue: UUID(uuidString: "A3C00300-0003-4000-8000-000000000012")!))
        let result = try await actions.runRecipe(recipe, importTitle: "Original workbench sample", into: collection, request: request, staging: staging)
        #expect(result.job.state == .completed)
        #expect(result.job.completedUnits == 4)
        #expect(result.importReceipt?.admitted.adapter == .appUI)
        #expect(result.transformReceipt == result.importReceipt)
        let items = try await backend.items(inbox, via: .appUI)
        #expect(items.map(\.id) == [request.newItemID])
        #expect(items.first?.note.value == " · recipe transform")
        #expect(catalog.recipe(recipe.id)?.sourceItemIDs == [request.newItemID])
        #expect(result.export?.recipe.sourceItemIDs == [request.newItemID])
        #expect(await staging.pendingCount == 0)
        let freshExport = try #require(result.export)
        #expect(freshExport.withheld.isEmpty)

        // Typed text never leaves in an export, whatever its field is called.
        let sentinel = "original-synthetic-secret-sentinel"
        let typed = RecipeDefinition(
            id: RecipeID(rawValue: UUID(uuidString: "A3C00300-0003-4000-8000-000000000013")!),
            title: "Original typed title \(sentinel)",
            steps: [RecipeStep(order: 1, kind: .query, detail: sentinel), RecipeStep(order: 2, kind: .export)],
            sourceItemIDs: [request.newItemID],
            modelStep: ModelStepPayload(fields: [
                "prompt": sentinel, "instructions_v2": sentinel, sentinel: "neutral",
                "config": #"{"auth":{"key":"\#(sentinel)"}}"#, "tone": "neutral",
            ])
        )
        let typedExport = RecipeExport(recipe: typed)
        #expect(!typedExport.containsRawSecret([sentinel, "instructions_v2", "config"]))
        #expect(typedExport.withheld == RecipeExportWithholding(title: true, stepDetails: [1], modelStepValues: ["prompt"], unnamedModelStepFields: 3))
        let model = ShortcutWorkbenchModel()
        model.connect(library)
        model.export(typed)
        #expect(model.lastExportText == typedExport.text)
        #expect(model.lastMessage?.contains("Withheld") == true)
        let saved = folder.appending(path: typedExport.filename)
        try typedExport.write(to: saved)
        #expect(try Data(contentsOf: saved) == typedExport.data)
        #expect(!String(decoding: try Data(contentsOf: saved), as: UTF8.self).contains(sentinel))

        let record = try EvidenceRecord(
            subject: "LAB-003",
            check: "Host backend: fresh four-step recipe in one commit, refusal before commit, and typed-text export withholding",
            date: Date(), provenance: .current, execution: .fixture,
            inputs: [
                "fresh-walkthrough-export@sha256:" + SHA256.hash(data: freshExport.data).map { String(format: "%02x", $0) }.joined(),
                "typed-sentinel-export@sha256:" + SHA256.hash(data: typedExport.data).map { String(format: "%02x", $0) }.joined(),
            ],
            steps: [
                "Run ShortcutWorkbenchQualificationHostTests in the built host test action",
                "Open a fresh SQLite store; create Qualification inbox; run an unbound transform recipe and confirm it is refused with an empty inbox and no draft",
                "Run the unbound bundled Import → Query → Transform → Export recipe through LibraryWorkbenchBackend with a fixed request ID",
                "Export an original recipe holding an invented sentinel in its title, a query, and model-step values under ordinary, new, nested and sentinel names; save it with RecipeExport.write and read the file back",
                "Connect a fresh ShortcutWorkbenchModel and compare its export text and message"
            ],
            outcome: .passed(observed: "The unbound transform recipe was refused before commit. The fresh recipe completed four steps with one appUI createItem receipt carrying the transform; the new item was bound as the recipe source. The sentinel was absent from the export bytes, the saved file and the filename; the message reported the withheld positions. The lab-written walkthrough exported with nothing withheld."),
            limitations: [
                "Fixture invocation inside the host, not a Shortcuts, Siri, Storage or model execution. No UI controls or assistive technology were driven.",
                "The sentinel is invented. Export safety is proven for recipe exports and the Inspect Model Step result; the in-app inspection still shows typed values with secret-shaped names masked.",
                "No physical mobile device, cross-device identity or durable recipe persistence was tested."
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        Attachment.record(String(decoding: try encoder.encode(record), as: UTF8.self), named: "LAB-003-host-fresh-recipe.json")
        #expect(record.provenance.xcodeBuild != "unknown")
    }
}
