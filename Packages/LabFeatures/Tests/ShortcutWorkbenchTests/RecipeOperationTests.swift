import Foundation
import LabDomain
import Testing
@testable import ShortcutWorkbench

@Suite struct RecipeOperationTests {
    @Test func curatedEntriesStayUnderTheAppShortcutsCapAndApartFromAtomicSamples() {
        let curated = TypedActionContract.curated
        #expect(curated.count <= ShortcutWorkbench.curatedShortcutCap)
        #expect(curated.count == 6)
        #expect(Set(curated.map(\.layer)) == [.curated])
        #expect(Set(TypedActionContract.atomicSamples.map(\.layer)) == [.atomic])
        #expect(Set(curated.map(\.id)).isDisjoint(with: Set(TypedActionContract.atomicSamples.map(\.id))))
    }

    @Test func aRecipeSurvivesRenamingItsSourceItem() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let actions = backend.actions(.appUI, catalog: catalog)

        // Bind amber by stable ID, then rename it through the operation service.
        var recipe = RecipeDefinition.importExportWalkthrough(sourceItemIDs: [TestSeed.amber])
        recipe.steps = [
            RecipeStep(order: 1, kind: .query, detail: "ignored-when-bound"),
            RecipeStep(order: 2, kind: .export),
        ]
        actions.saveRecipe(recipe)

        let before = try await actions.resolveItem(TestSeed.amber)
        #expect(before.title.value == "Amber sample")

        let rename = DomainOperation.updateItem(
            id: TestSeed.amber,
            expected: before.revision,
            changes: try ItemChanges(title: try EntityTitle("Renamed amber"))
        )
        _ = try await backend.commit(rename, requestID: RequestID(), authority: .appControl, names: [.item(TestSeed.amber): "Renamed amber"])

        let after = try await actions.resolveItem(TestSeed.amber)
        #expect(after.title.value == "Renamed amber")
        #expect(after.id == TestSeed.amber)

        let result = try await actions.runRecipe(recipe, into: nil, request: WorkbenchRequest(), staging: RecipeImportStaging())
        #expect(result.job.state == .completed)
        #expect(result.matched.map(\.id) == [TestSeed.amber])
        #expect(result.matched.first?.title.value == "Renamed amber")
    }

    @Test func cancellationDoesNotLeaveHalfAnImport() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let actions = backend.actions(.appUI, catalog: catalog)
        let staging = RecipeImportStaging()

        let ownID = CollectionID()
        let create = DomainOperation.createCollection(draft: CollectionDraft(id: ownID, title: try EntityTitle("Workbench")))
        _ = try await backend.commit(create, requestID: RequestID(), authority: .appControl, names: [.collection(ownID): "Workbench"])

        let draft = try await actions.beginImport(title: "Half import", note: "should not commit", into: ownID, staging: staging)
        #expect(await staging.pendingCount == 1)

        await actions.cancelImport(draft, staging: staging)
        #expect(await staging.pendingCount == 0)

        await #expect(throws: WorkbenchError.self) {
            try await actions.commitImport(draft, into: ownID, request: WorkbenchRequest(), staging: staging)
        }
        #expect(backend.commitCount == 1, "only the collection create committed; the cancelled import did not")
    }

    @Test func cancellingAfterStagingBeforeCommitLeavesNothing() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let actions = backend.actions(.appUI, catalog: WorkbenchRecipeCatalog(seed: []))
        let staging = RecipeImportStaging()
        let ownID = CollectionID()
        _ = try await backend.commit(
            .createCollection(draft: CollectionDraft(id: ownID, title: try EntityTitle("Inbox"))),
            requestID: RequestID(),
            authority: .appControl,
            names: [.collection(ownID): "Inbox"]
        )
        let beforeItems = try await backend.items(try ItemFilter(includeArchived: true, limit: 50), via: .appUI).count

        let draft = try await actions.beginImport(title: "Abandoned", into: ownID, staging: staging)
        await actions.cancelImport(draft, staging: staging)

        let afterItems = try await backend.items(try ItemFilter(includeArchived: true, limit: 50), via: .appUI).count
        #expect(afterItems == beforeItems)
        #expect(await staging.pendingCount == 0)
    }

    @Test func rawSecretValuesNeverEnterRecipeExports() throws {
        let secret = "super-secret-api-key-value-9f3a"
        let recipe = RecipeDefinition(
            id: RecipeID(),
            title: "Secret-bearing recipe",
            steps: [RecipeStep(order: 1, kind: .export)],
            modelStep: ModelStepPayload(fields: [
                "prompt": "Summarize the lab.",
                "apiKey": secret,
                "password": "hunter2",
                "tone": "neutral",
            ])
        )
        let export = RecipeExport(recipe: recipe)
        #expect(export.redactedKeys.sorted() == ["apiKey", "password"])
        #expect(!export.containsRawSecret([secret, "hunter2"]))
        #expect(export.text.contains(SecretRedaction.placeholder))
        #expect(export.text.contains("Summarize the lab."))
        #expect(export.text.contains("neutral"))
        #expect(!export.text.contains(secret))
        #expect(!export.text.contains("hunter2"))
    }

    @Test func modelStepInspectionRedactsSecrets() {
        let inspection = ModelStepInspection(payload: ModelStepPayload(fields: [
            "prompt": "Hello",
            "token": "abc123token",
        ]))
        #expect(inspection.fields["prompt"] == "Hello")
        #expect(inspection.fields["token"] == SecretRedaction.placeholder)
        #expect(inspection.redactedKeys == ["token"])
        #expect(inspection.summary.contains("token"))
        #expect(!inspection.summary.contains("abc123token"))
    }

    @Test func fallbackCopyMatchesTheRegistration() {
        #expect(WorkbenchFallback.text == "Manual recipe instructions and app action browser; no secret storage inside Shortcuts.")
        #expect(!ManualRecipeCard.all.isEmpty)
        #expect(ManualRecipeCard.all.contains { $0.notes.contains("Shortcuts Storage") || $0.notes.contains("passwords") || $0.notes.contains("API keys") })
    }

    @Test func sensitiveTransformSharesTheDomainCommitPath() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let actions = backend.actions(.appUI, catalog: catalog)
        var recipe = RecipeDefinition(
            id: RecipeID(),
            title: "Transform only",
            steps: [RecipeStep(order: 1, kind: .transform, detail: " · via workbench")],
            sourceItemIDs: [TestSeed.kraft]
        )
        actions.saveRecipe(recipe)

        let before = backend.commitCount
        let result = try await actions.runRecipe(recipe, into: nil, request: WorkbenchRequest(), staging: RecipeImportStaging())
        #expect(result.job.state == .completed)
        #expect(result.transformReceipt != nil)
        #expect(backend.commitCount == before + 1)
        let (operation, authority) = backend.commits.withLock { $0.last! }
        #expect(authority == .appControl)
        if case .updateItem(let id, _, _) = operation {
            #expect(id == TestSeed.kraft)
        } else {
            Issue.record("expected updateItem, got \(operation)")
        }
        let updated = try await actions.resolveItem(TestSeed.kraft)
        #expect(updated.note.value.hasSuffix(" · via workbench"))
    }

    @Test func unavailableBackendRefusesWithoutCommitting() async throws {
        let actions = WorkbenchActions(backend: UnavailableWorkbenchBackend(reason: "closed"), entryPoint: .appUI)
        await #expect(throws: WorkbenchError.self) {
            try await actions.resolveItem(TestSeed.amber)
        }
    }

    @Test func invalidRecipeIDIsRefused() throws {
        let actions = WorkbenchActions(
            backend: UnavailableWorkbenchBackend(reason: "unused"),
            entryPoint: .appUI,
            catalog: WorkbenchRecipeCatalog(seed: [])
        )
        #expect(throws: WorkbenchError.self) {
            try actions.recipe(RecipeID())
        }
    }
}
