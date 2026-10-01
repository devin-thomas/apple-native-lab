import ShortcutWorkbench
import SwiftUI

/// Shortcut Workbench list column on the Mac.
struct ShortcutWorkbenchListColumn: View {
    @Bindable var window: MainWindowState
    @State private var model = ShortcutWorkbenchModel.shared

    var body: some View {
        List(selection: $window.workbenchRecipeID) {
            Section {
                ForEach(model.recipes) { recipe in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.title)
                        Text(recipe.steps.map(\.kind.rawValue).joined(separator: " → "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(recipe.id))
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Recipes")
            }
            Section {
                ForEach(ManualRecipeCard.all) { card in
                    Text(card.title)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Manual fallback")
            } footer: {
                Text(WorkbenchFallback.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle(ShortcutWorkbench.title)
        .task { model.refresh() }
    }
}

struct ShortcutWorkbenchDetailColumn: View {
    @Bindable var window: MainWindowState
    @State private var model = ShortcutWorkbenchModel.shared

    var body: some View {
        if let id = window.workbenchRecipeID, let recipe = model.recipes.first(where: { $0.id == id }) {
            RecipeDetailPage(recipe: recipe, model: model)
        } else {
            ShortcutWorkbenchPage()
        }
    }
}
