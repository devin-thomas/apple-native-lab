import ActionAtlas
import Foundation
import LabDomain
import Testing
@testable import ShortcutWorkbench

@Suite struct WorkbenchIntentTests {
    @Test func resolveIntentFindsAnItemAfterRename() async throws {
        let backend = try await TestWorkbenchBackend.seeded()
        let actions = WorkbenchActions(backend: backend, entryPoint: .appUI, catalog: WorkbenchRecipeCatalog(seed: []))

        let before = try await actions.resolveItem(TestSeed.amber)
        _ = try await backend.commit(
            .updateItem(
                id: TestSeed.amber,
                expected: before.revision,
                changes: try ItemChanges(title: try EntityTitle("Still amber by ID"))
            ),
            requestID: RequestID(),
            authority: .appControl,
            names: [.item(TestSeed.amber): "Still amber by ID"]
        )

        var intent = ResolveLabItemIntent()
        intent.item = LabItemEntity(before, collectionTitle: "Pigments")
        let output = try await intent.run(with: WorkbenchLink(backend: backend))
        #expect(output.value.title == "Still amber by ID")
        #expect(output.value.id == TestSeed.amber.rawValue)
        #expect(output.dialog.contains("identifier is unchanged"))
    }

    @Test func exportRecipeIntentRedactsSecrets() throws {
        let secret = "live-secret-value"
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let id = RecipeID(rawValue: UUID(uuidString: "A3C00300-0001-4000-8000-000000000099")!)
        catalog.save(RecipeDefinition(
            id: id,
            title: "With secret",
            steps: [RecipeStep(order: 1, kind: .export)],
            modelStep: ModelStepPayload(fields: ["api_key": secret, "prompt": "ok"])
        ))
        let actions = WorkbenchActions(
            backend: UnavailableWorkbenchBackend(reason: "unused"),
            entryPoint: .appIntent,
            catalog: catalog
        )
        let export = try actions.exportRecipe(id: id)
        #expect(!export.containsRawSecret([secret]))
        #expect(export.redactedKeys == ["api_key"])
    }

    @Test func inspectModelStepIntentReportsRedaction() async throws {
        let catalog = WorkbenchRecipeCatalog(seed: [])
        let id = RecipeID(rawValue: UUID(uuidString: "A3C00300-0001-4000-8000-000000000088")!)
        catalog.save(RecipeDefinition(
            id: id,
            title: "With model step",
            steps: [RecipeStep(order: 1, kind: .export)],
            modelStep: ModelStepPayload(fields: ["prompt": "Summarize", "clientSecret": "nope"])
        ))
        // Intent uses the shared catalog; seed the same recipe there.
        WorkbenchRecipeCatalog.shared.save(RecipeDefinition(
            id: id,
            title: "With model step",
            steps: [RecipeStep(order: 1, kind: .export)],
            modelStep: ModelStepPayload(fields: ["prompt": "Summarize", "clientSecret": "nope"])
        ))
        var intent = InspectModelStepIntent()
        intent.recipeID = id.rawValue.uuidString
        let output = try await intent.run(with: WorkbenchLink(backend: UnavailableWorkbenchBackend(reason: "unused")))
        #expect(output.value.contains(SecretRedaction.placeholder))
        #expect(!output.value.contains("nope"))
        #expect(output.dialog.contains("clientSecret") || output.value.contains("clientSecret"))
        _ = catalog
    }

    @Test func curatedShortcutCountStaysAtOrUnderTen() {
        #expect(TypedActionContract.curated.count <= ShortcutWorkbench.curatedShortcutCap)
        #expect(TypedActionContract.curated.count == 6)
    }
}
