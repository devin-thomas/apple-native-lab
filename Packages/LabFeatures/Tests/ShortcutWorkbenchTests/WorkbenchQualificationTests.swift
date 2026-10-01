import ActionAtlas
import Foundation
import LabDomain
import Testing
@testable import ShortcutWorkbench

/// Qualification checks: the fresh run, refusal before commit, and the export rule.
@Suite struct WorkbenchQualificationTests {
    private func inbox(_ backend: TestWorkbenchBackend) async throws -> CollectionID {
        let id = CollectionID(rawValue: UUID(uuidString: "A3C00300-0002-4000-8000-000000000001")!)
        _ = try await backend.commit(
            .createCollection(draft: CollectionDraft(id: id, title: EntityTitle("Qualification inbox"))),
            requestID: RequestID(), authority: .appControl, names: [:]
        )
        return id
    }

    @Test func boundRecipeCompletesAndResetLeavesImportedUserDataAlone() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let id = try await inbox(backend)
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let actions = backend.actions(.appUI, catalog: catalog)
        let staging = RecipeImportStaging()
        let request = WorkbenchRequest(RequestID(rawValue: UUID(uuidString: "A3C00300-0002-4000-8000-000000000002")!))
        let draft = try await actions.beginImport(title: "Original workbench sample", note: "Original neutral text.", into: id, staging: staging)
        let imported = try await actions.commitImport(draft, into: id, request: request, staging: staging)
        var recipe = RecipeDefinition.importExportWalkthrough(sourceItemIDs: [imported.entity.id])
        recipe.steps.removeAll { $0.kind == .importDocument }
        actions.saveRecipe(recipe)
        let result = try await actions.runRecipe(recipe, into: nil, request: WorkbenchRequest(), staging: staging)
        #expect(result.job.state == .completed)
        #expect(result.job.completedUnits == 3)
        #expect(result.transformReceipt?.status == .committed)
        #expect(result.matched.first?.note.value == "Original neutral text. · recipe transform")
        #expect(result.export?.recipe.sourceItemIDs == [imported.entity.id])
        let beforeReset = try await actions.resolveItem(imported.entity.id)
        let reset = DomainOperation.resetDemo(seed: TestSeed.seed)
        let grant = try backend.ledger.issue(for: reset, to: .appUI)
        defer { backend.ledger.revoke(grant.id) }
        _ = try await backend.service.perform(OperationRequest(id: RequestID(), operation: reset, actor: TestWorkbenchBackend.appUI))
        #expect(try await actions.resolveItem(imported.entity.id) == beforeReset)
        #expect(catalog.recipe(recipe.id) == recipe)
        #expect(await staging.pendingCount == 0)
    }

    @Test func freshFourStepRunBindsItsImportAndCompletesInOneCommit() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let id = try await inbox(backend)
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let actions = backend.actions(.appUI, catalog: catalog)
        let request = WorkbenchRequest()
        let staging = RecipeImportStaging()
        let recipe = RecipeDefinition.importExportWalkthrough()
        let before = backend.commitCount
        let result = try await actions.runRecipe(recipe, importTitle: "Original workbench sample", into: id, request: request, staging: staging)
        #expect(result.job.state == .completed)
        #expect(result.job.completedUnits == 4)
        #expect(backend.commitCount == before + 1, "import and transform are one commit")
        let (operation, authority) = try #require(backend.commits.withLock { $0.last })
        #expect(authority == .appControl)
        guard case .createItem(let draft) = operation else {
            Issue.record("expected createItem, got \(operation)")
            return
        }
        #expect(draft.id == request.newItemID)
        #expect(draft.note.value == " · recipe transform")
        #expect(result.importReceipt?.status == .committed)
        #expect(result.transformReceipt == result.importReceipt)
        #expect(result.matched.map(\.id) == [request.newItemID])
        #expect(result.matched.first?.note.value == " · recipe transform")
        #expect(result.export?.recipe.sourceItemIDs == [request.newItemID])
        #expect(catalog.recipe(recipe.id)?.sourceItemIDs == [request.newItemID])
        #expect(await staging.pendingCount == 0)

        // A retry with the same request replays the first receipt and stores nothing new.
        let retry = try await actions.runRecipe(recipe, importTitle: "Original workbench sample", into: id, request: request, staging: staging)
        #expect(retry.job.state == .completed)
        #expect(retry.importReceipt == result.importReceipt)
        #expect(try await actions.resolveItem(request.newItemID).revision == .initial)
        #expect(await staging.pendingCount == 0)
    }

    /// Recipes that cannot complete, each refused before anything is staged or committed.
    enum Unrunnable: String, CaseIterable, Sendable {
        case transformWithoutSource, transformBeforeImport, twoImports, importWithoutCollection
        case unknownCollection, transformedNoteTooLong, invalidQuery, missingBoundSource
    }

    @Test(arguments: Unrunnable.allCases)
    func unrunnableRecipeIsRefusedBeforeAnythingIsStagedOrCommitted(_ shape: Unrunnable) async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let id = try await inbox(backend)
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let actions = backend.actions(.appUI, catalog: catalog)
        let staging = RecipeImportStaging()
        var collection: CollectionID? = id
        var note = ""
        let steps: [RecipeStep]
        var sources: [ItemID] = []
        switch shape {
        case .transformWithoutSource:
            steps = [RecipeStep(order: 1, kind: .query, detail: "sample"), RecipeStep(order: 2, kind: .transform, detail: " · t"), RecipeStep(order: 3, kind: .export)]
        case .transformBeforeImport:
            steps = [RecipeStep(order: 1, kind: .transform, detail: " · t"), RecipeStep(order: 2, kind: .importDocument)]
        case .twoImports:
            steps = [RecipeStep(order: 1, kind: .importDocument), RecipeStep(order: 2, kind: .importDocument)]
        case .importWithoutCollection:
            steps = RecipeDefinition.importExportWalkthrough().steps
            collection = nil
        case .unknownCollection:
            steps = RecipeDefinition.importExportWalkthrough().steps
            collection = CollectionID()
        case .transformedNoteTooLong:
            steps = RecipeDefinition.importExportWalkthrough().steps
            note = String(repeating: "n", count: ItemNote.maximumLength - 2)
        case .invalidQuery:
            steps = [RecipeStep(order: 1, kind: .importDocument), RecipeStep(order: 2, kind: .query, detail: String(repeating: "q", count: ItemFilter.maximumTextLength + 1))]
        case .missingBoundSource:
            steps = [RecipeStep(order: 1, kind: .transform, detail: " · t")]
            sources = [ItemID()]
        }
        let recipe = RecipeDefinition(title: "Original unrunnable fixture", steps: steps, sourceItemIDs: sources)
        actions.saveRecipe(recipe)
        let before = backend.commitCount
        let items = try await backend.items(try ItemFilter(includeArchived: true, limit: 200), via: .appUI)
        await #expect(throws: WorkbenchError.self) {
            try await actions.runRecipe(recipe, importTitle: "Original fixture", importNote: note, into: collection, request: WorkbenchRequest(), staging: staging)
        }
        #expect(backend.commitCount == before)
        #expect(try await backend.items(try ItemFilter(includeArchived: true, limit: 200), via: .appUI) == items)
        #expect(await staging.pendingCount == 0)
        #expect(catalog.recipe(recipe.id) == recipe)
    }

    @Test func refusedImportCommitLeavesNoDraftAndKeepsThePreviousBinding() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let id = try await inbox(backend)
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let actions = backend.actions(.appIntent, catalog: catalog)
        let staging = RecipeImportStaging()
        let request = WorkbenchRequest()
        let recipe = RecipeDefinition.importExportWalkthrough()
        _ = try await actions.runRecipe(recipe, importTitle: "Original first sample", into: id, request: request, staging: staging)
        let bound = try #require(catalog.recipe(recipe.id))
        let items = try await backend.items(try ItemFilter(includeArchived: true, limit: 200), via: .appUI)
        // Same request, different payload: the operation service refuses at the commit itself.
        await #expect(throws: WorkbenchError.refused(.requestIDReused(request.id))) {
            try await actions.runRecipe(bound, importTitle: "Original changed sample", into: id, request: request, staging: staging)
        }
        #expect(try await backend.items(try ItemFilter(includeArchived: true, limit: 200), via: .appUI) == items)
        #expect(await staging.pendingCount == 0)
        #expect(catalog.recipe(recipe.id) == bound)
    }

    @Test func cancelledFreshRunCommitsNothing() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let id = try await inbox(backend)
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let actions = backend.actions(.appUI, catalog: catalog)
        let staging = RecipeImportStaging()
        let before = backend.commitCount
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await actions.runRecipe(RecipeDefinition.importExportWalkthrough(), importTitle: "Cancelled fixture", into: id, request: WorkbenchRequest(), staging: staging)
        }
        let result = try await task.value
        #expect(result.job.state == .cancelled)
        #expect(result.importReceipt == nil)
        #expect(backend.commitCount == before)
        #expect(await staging.pendingCount == 0)
        #expect(catalog.recipe(RecipeDefinition.importExportWalkthrough().id) == nil)
    }

    @Test func duplicateImportReplaysReceiptAndChangedPayloadIsRefused() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let id = try await inbox(backend)
        let actions = backend.actions(.appIntent, catalog: WorkbenchRecipeCatalog(seed: []))
        let staging = RecipeImportStaging()
        let request = WorkbenchRequest()
        let firstDraft = try await actions.beginImport(title: "Original sample", into: id, staging: staging)
        let first = try await actions.commitImport(firstDraft, into: id, request: request, staging: staging)
        let retryDraft = try await actions.beginImport(title: "Original sample", into: id, staging: staging)
        let retry = try await actions.commitImport(retryDraft, into: id, request: request, staging: staging)
        #expect(first.receipt == retry.receipt)
        #expect(try await actions.resolveItem(request.newItemID).revision == .initial)
        let changed = try await actions.beginImport(title: "Different payload", into: id, staging: staging)
        await #expect(throws: WorkbenchError.refused(.requestIDReused(request.id))) {
            try await actions.commitImport(changed, into: id, request: request, staging: staging)
        }
        await actions.cancelImport(changed, staging: staging)
        #expect(await staging.pendingCount == 0)
    }

    @Test func staleAndDeniedCommitsLeaveTheItemUnchanged() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let original = try await backend.actions(.appUI).resolveItem(TestSeed.amber)
        _ = try await backend.commit(
            .updateItem(id: original.id, expected: original.revision, changes: ItemChanges(title: EntityTitle("Renamed fixture"))),
            requestID: RequestID(), authority: .appControl, names: [:]
        )
        let stale = DomainOperation.updateItem(id: original.id, expected: original.revision, changes: try ItemChanges(note: ItemNote("Stale note")))
        let receipt = try await backend.commit(stale, requestID: RequestID(), authority: .intent, names: [:])
        #expect(receipt.conflict != nil)
        let current = try await backend.actions(.appUI).resolveItem(original.id)
        let denied = ActorScope(adapter: .appIntent, grants: [])
        await #expect(throws: OperationError.self) {
            try await backend.service.perform(OperationRequest(id: RequestID(), operation: stale, actor: denied))
        }
        #expect(try await backend.actions(.appUI).resolveItem(original.id) == current)
    }

    @Test func taskCancellationBeforeCommitDiscardsDraft() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let id = try await inbox(backend)
        let actions = backend.actions(.appUI)
        let staging = RecipeImportStaging()
        let draft = try await actions.beginImport(title: "Cancelled fixture", into: id, staging: staging)
        let before = backend.commitCount
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: WorkbenchError.cancelled) {
                try await actions.commitImport(draft, into: id, request: WorkbenchRequest(), staging: staging)
            }
        }
        await task.value
        #expect(await staging.pendingCount == 0)
        #expect(backend.commitCount == before)
    }

    @Test func exportIntentHelperReturnsWithheldBytes() async throws {
        let id = RecipeID(rawValue: UUID(uuidString: "A3C00300-0002-4000-8000-000000000099")!)
        let recipe = RecipeDefinition(id: id, title: "Original export fixture", steps: [], modelStep: ModelStepPayload(fields: ["API_KEY": "original-synthetic-secret-sentinel", "prompt": "Original neutral text."]))
        WorkbenchRecipeCatalog.shared.save(recipe)
        defer { WorkbenchRecipeCatalog.shared.remove(id) }
        let intent = ExportRecipeIntent()
        intent.recipeID = id.rawValue.uuidString
        let output = try await intent.run(with: WorkbenchLink.unavailable)
        #expect(!output.value.containsRawSecret(["original-synthetic-secret-sentinel", "Original neutral text.", "API_KEY", "Original export fixture"]))
        #expect(output.value.withheld == RecipeExportWithholding(title: true, stepDetails: [], modelStepValues: ["prompt"], unnamedModelStepFields: 1))
        #expect(output.value.filename == "Lab recipe.recipe.json")
        #expect(output.dialog.contains("Withheld"))
        #expect(!output.dialog.contains("original-synthetic-secret-sentinel"))
    }

    static let sentinel = "original-synthetic-secret-sentinel"

    /// A sentinel in every place a person can type text into a recipe. Field names never decide.
    static let typedPlacements: [RecipeDefinition] = {
        let s = sentinel
        var cases: [RecipeDefinition] = []
        // Values under secret-shaped, ordinary, new, and renamed names.
        for key in ["API_KEY", "userPassword", "access-token", "client.secret", "Cookie", "PRIVATE_KEY",
                    "prompt", "tone", "instructions", "context", "x", "prompt_v2", "Prompt", "p r o m p t", "notes.extra"] {
            cases.append(RecipeDefinition(title: "Query → Report", steps: [], modelStep: ModelStepPayload(fields: [key: s])))
        }
        // The sentinel as a field name, and nested or embedded inside longer values.
        cases.append(RecipeDefinition(title: "Query → Report", steps: [], modelStep: ModelStepPayload(fields: [s: "neutral"])))
        cases.append(RecipeDefinition(title: "Query → Report", steps: [], modelStep: ModelStepPayload(fields: ["prompt": #"{"auth":{"key":"\#(s)"}}"#])))
        cases.append(RecipeDefinition(title: "Query → Report", steps: [], modelStep: ModelStepPayload(fields: ["prompt": "Summarize matching lab items. \(s)"])))
        cases.append(RecipeDefinition(title: "Query → Report", steps: [], modelStep: ModelStepPayload(fields: ["config": "key=\(s)\nmode=neutral"])))
        // Recipe text outside the model step.
        cases.append(RecipeDefinition(title: s, steps: []))
        cases.append(RecipeDefinition(title: "Query → Report", steps: [RecipeStep(order: 1, kind: .query, detail: s)]))
        cases.append(RecipeDefinition(title: "Query → Report", steps: [RecipeStep(order: 1, kind: .transform, detail: " · \(s)")]))
        return cases
    }()

    @Test(arguments: typedPlacements)
    func exportWithholdsTypedTextWhateverItsFieldIsCalled(_ recipe: RecipeDefinition) throws {
        let export = RecipeExport(recipe: recipe)
        #expect(!export.containsRawSecret([Self.sentinel]))
        #expect(!export.filename.contains(Self.sentinel))
        #expect(!export.withheld.isEmpty)
        #expect(!(export.withheld.summary ?? "").contains(Self.sentinel))
        #expect(!ModelStepExportView(payload: recipe.modelStep ?? ModelStepPayload()).text.contains(Self.sentinel))
        // The document still parses and keeps its structure.
        let object = try #require(try JSONSerialization.jsonObject(with: export.data) as? [String: Any])
        #expect(object["id"] as? String == recipe.id.rawValue.uuidString)
        #expect((object["steps"] as? [Any])?.count == recipe.steps.count)
    }

    @Test func bundledRecipesExportInFullBecauseTheLabWroteThem() throws {
        for recipe in WorkbenchRecipeCatalog.bundledRecipes {
            let export = RecipeExport(recipe: recipe)
            #expect(export.withheld.isEmpty)
            #expect(export.withheld.summary == nil)
            #expect(export.text.contains(recipe.title))
            for (key, value) in recipe.modelStep?.fields ?? [:] {
                #expect(export.text.contains(key) && export.text.contains(value))
            }
            #expect(!export.text.contains(RecipeExport.withheldPlaceholder))
        }
    }
}
