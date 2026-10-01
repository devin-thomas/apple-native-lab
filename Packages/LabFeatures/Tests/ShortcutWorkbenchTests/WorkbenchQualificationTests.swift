import ActionAtlas
import Foundation
import LabDomain
import Testing
@testable import ShortcutWorkbench

/// Qualification observations, including limits of the currently shipped recipe runner.
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

    @Test func freshFourStepRunCurrentlyCommitsImportThenRefusesUnboundTransform() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let id = try await inbox(backend)
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let actions = backend.actions(.appUI, catalog: catalog)
        let request = WorkbenchRequest()
        let staging = RecipeImportStaging()
        let recipe = RecipeDefinition.importExportWalkthrough()
        await #expect(throws: WorkbenchError.invalidInput("This recipe has no source item to transform.")) {
            try await actions.runRecipe(recipe, importTitle: "Original workbench sample", into: id, request: request, staging: staging)
        }
        #expect(try await actions.resolveItem(request.newItemID).note.value == "")
        #expect(catalog.recipe(recipe.id)?.sourceItemIDs == [request.newItemID])
        #expect(await staging.pendingCount == 0)
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

    @Test func exportIntentHelperReturnsRedactedBytes() async throws {
        let id = RecipeID(rawValue: UUID(uuidString: "A3C00300-0002-4000-8000-000000000099")!)
        let recipe = RecipeDefinition(id: id, title: "Original export fixture", steps: [], modelStep: ModelStepPayload(fields: ["API_KEY": "original-synthetic-secret-sentinel", "prompt": "Original neutral text."]))
        WorkbenchRecipeCatalog.shared.save(recipe)
        defer { WorkbenchRecipeCatalog.shared.remove(id) }
        var intent = ExportRecipeIntent()
        intent.recipeID = id.rawValue.uuidString
        let output = try await intent.run(with: WorkbenchLink.unavailable)
        #expect(!output.value.containsRawSecret(["original-synthetic-secret-sentinel"]))
        #expect(output.value.redactedKeys == ["API_KEY"])
    }

    @Test func redactionCoversSecretShapedKeysButNotArbitraryText() {
        let sentinel = "original-synthetic-secret-sentinel"
        for key in ["API_KEY", "userPassword", "access-token", "client.secret", "Cookie", "PRIVATE_KEY"] {
            let recipe = RecipeDefinition(title: "Original fixture", steps: [], modelStep: ModelStepPayload(fields: [key: sentinel]))
            #expect(!RecipeExport(recipe: recipe).containsRawSecret([sentinel]))
        }
        let recipe = RecipeDefinition(title: "Original fixture", steps: [], modelStep: ModelStepPayload(fields: ["prompt": sentinel]))
        #expect(RecipeExport(recipe: recipe).containsRawSecret([sentinel]), "Current limitation: ordinary text is not a secret detector")
    }
}
