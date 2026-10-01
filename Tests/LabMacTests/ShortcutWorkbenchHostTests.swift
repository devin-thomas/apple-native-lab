import ShortcutWorkbench
import Testing

@Suite struct ShortcutWorkbenchHostTests {
    @Test func curatedContractsAndFallbackMatchTheModule() {
        #expect(ShortcutWorkbench.title == "Shortcut Workbench")
        #expect(ShortcutWorkbench.experimentID == "LAB-003")
        #expect(TypedActionContract.curated.count == 6)
        #expect(TypedActionContract.curated.count <= ShortcutWorkbench.curatedShortcutCap)
        #expect(Set(TypedActionContract.curated.map(\.layer)) == [.curated])
        #expect(WorkbenchFallback.text == "Manual recipe instructions and app action browser; no secret storage inside Shortcuts.")
        #expect(!ManualRecipeCard.all.isEmpty)
        #expect(WorkbenchRecipeCatalog.bundledRecipes.count >= 2)
    }
}
