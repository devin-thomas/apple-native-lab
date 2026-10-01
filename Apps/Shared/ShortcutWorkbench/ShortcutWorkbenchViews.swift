import LabCatalog
import LabDomain
import ShortcutWorkbench
import SwiftUI

/// The Shortcut Workbench page: curated entries, recipes, manual fallback, and the action browser link.
struct ShortcutWorkbenchPage: View {
    @State private var model = ShortcutWorkbenchModel.shared

    var body: some View {
        List {
            Section {
                Text("Curated App Shortcuts are a small set (at most ten). The Action Atlas tab is the larger atomic library and the declared fallback when Shortcuts is unavailable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(model.curated) { contract in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contract.title)
                            .font(.body.weight(.semibold))
                        Text(contract.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Curated entries")
            } footer: {
                Text("These six are declared through AppShortcutsProvider. Archive and Create stay in the atomic library.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(model.recipes) { recipe in
                    NavigationLink {
                        RecipeDetailPage(recipe: recipe, model: model)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.title)
                            Text(recipe.steps.map(\.kind.rawValue).joined(separator: " → "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Recipes")
            }

            Section {
                ForEach(ManualRecipeCard.all) { card in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.title)
                            .font(.body.weight(.semibold))
                        ForEach(Array(card.steps.enumerated()), id: \.offset) { index, step in
                            Text("\(index + 1). \(step)")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(card.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Manual fallback")
            } footer: {
                Text(WorkbenchFallback.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = model.lastMessage {
                Section {
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                    if let export = model.lastExportText {
                        Text(export)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Latest result")
                }
            }

            if case .unavailable(let reason) = model.phase {
                Section {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(ShortcutWorkbench.title)
        .task { model.refresh() }
    }
}

struct RecipeDetailPage: View {
    let recipe: RecipeDefinition
    let model: ShortcutWorkbenchModel
    @Environment(LabLibrary.self) private var library

    var body: some View {
        List {
            Section {
                ForEach(recipe.steps) { step in
                    LabeledContent(step.kind.rawValue.capitalized) {
                        Text(step.detail ?? "—")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Steps")
            }

            Section {
                if recipe.sourceItemIDs.isEmpty {
                    Text("None yet. Running the import step binds a stable identifier.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recipe.sourceItemIDs, id: \.rawValue) { id in
                        Text(id.rawValue.uuidString)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("Bound items")
            } footer: {
                Text("Titles can change; identifiers stay. A recipe that stored an identifier still resolves after a rename.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                if recipe.modelStep != nil {
                    Button("Inspect Model Step") {
                        model.inspect(recipe)
                    }
                }
                Button("Export Recipe") {
                    model.export(recipe)
                }
                if recipe.id == RecipeDefinition.importExportWalkthrough().id {
                    Button("Run Recipe") {
                        Task {
                            let own = library.collections.first {
                                $0.collection.namespace == .user && !$0.collection.isArchived
                            }
                            let demoItem = library.collections.flatMap(\.items).first { $0.namespace == .demo }
                            await model.runImportExport(
                                into: own?.id,
                                sourceItemID: recipe.sourceItemIDs.first ?? demoItem?.id
                            )
                        }
                    }
                    .disabled(!library.canAct)
                }
            }

            if let inspection = model.lastInspection {
                Section {
                    Text(inspection.summary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(inspection.fields.keys.sorted(), id: \.self) { key in
                        LabeledContent(key) {
                            Text(inspection.fields[key] ?? "")
                                .font(.caption.monospaced())
                        }
                    }
                } header: {
                    Text("Model step inspection")
                }
            }
        }
        .navigationTitle(recipe.title)
    }
}

/// Catalog launch into the workbench.
struct ShortcutWorkbenchLaunch: View {
    let experiment: RegisteredExperiment

    var body: some View {
        if experiment.id == ShortcutWorkbench.experimentID {
            #if os(iOS)
            NavigationLink {
                ShortcutWorkbenchPage()
            } label: {
                Label("Open \(ShortcutWorkbench.title)", systemImage: ShortcutWorkbench.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Curated recipes and manual instructions; no secret storage in Shortcuts.")
            #else
            EmptyView()
            #endif
        }
    }
}
