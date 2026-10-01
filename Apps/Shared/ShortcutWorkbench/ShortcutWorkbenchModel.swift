import LabDomain
import Observation
import ShortcutWorkbench

/// Session state for the Shortcut Workbench page: recipes, last run, and open requests from intents.
@MainActor
@Observable
final class ShortcutWorkbenchModel {
    static let shared = ShortcutWorkbenchModel()

    private(set) var openRequests = 0
    private(set) var recipes: [RecipeDefinition] = WorkbenchRecipeCatalog.shared.all()
    private(set) var curated: [TypedActionContract] = TypedActionContract.curated
    private(set) var lastMessage: String?
    private(set) var lastExportText: String?
    private(set) var lastInspection: ModelStepInspection?
    private(set) var phase: Phase = .idle

    enum Phase: Hashable {
        case idle
        case running
        case unavailable(String)
    }

    @ObservationIgnored private var library: LabLibrary?
    @ObservationIgnored let staging = RecipeImportStaging()
    @ObservationIgnored let catalog = WorkbenchRecipeCatalog.shared

    func connect(_ library: LabLibrary) {
        self.library = library
        refresh()
    }

    func requestOpen() {
        openRequests += 1
    }

    func refresh() {
        recipes = catalog.all()
        curated = TypedActionContract.curated
    }

    func actions() throws(WorkbenchError) -> WorkbenchActions {
        guard let library else {
            throw .unavailable(reason: "Native Lab has not opened its store yet.")
        }
        return WorkbenchActions(backend: LibraryWorkbenchBackend(library: library), entryPoint: .appUI, catalog: catalog)
    }

    func resolve(_ id: ItemID) async {
        do {
            let item = try await actions().resolveItem(id)
            lastMessage = "Resolved “\(item.title.value)” (revision \(item.revision.rawValue))."
            phase = .idle
        } catch {
            lastMessage = error.message
            if case .unavailable(let reason) = error {
                phase = .unavailable(reason)
            }
        }
    }

    func inspect(_ recipe: RecipeDefinition) {
        do {
            let inspection = try actions().inspectModelStep(of: recipe)
            lastInspection = inspection
            lastMessage = inspection.summary
        } catch {
            lastMessage = error.message
            lastInspection = nil
        }
    }

    func export(_ recipe: RecipeDefinition) {
        let exported = RecipeExport(recipe: recipe)
        lastExportText = exported.text
        if exported.redactedKeys.isEmpty {
            lastMessage = "Exported “\(recipe.title)” (\(exported.data.count) bytes)."
        } else {
            lastMessage = "Exported “\(recipe.title)”. Redacted: \(exported.redactedKeys.joined(separator: ", "))."
        }
    }

    func runImportExport(into collectionID: CollectionID?, sourceItemID: ItemID?) async {
        phase = .running
        do {
            let actions = try actions()
            var recipe = try actions.recipe(RecipeDefinition.importExportWalkthrough().id)
            if let sourceItemID {
                recipe.sourceItemIDs = [sourceItemID]
                recipe.steps = recipe.steps.filter { $0.kind != .importDocument }
                actions.saveRecipe(recipe)
            }
            let result = try await actions.runRecipe(
                recipe,
                importTitle: "Workbench import",
                into: collectionID,
                request: WorkbenchRequest(),
                staging: staging
            )
            lastMessage = result.job.summary
            if let export = result.export { lastExportText = export.text }
            refresh()
            phase = .idle
        } catch {
            lastMessage = error.message
            if case .unavailable(let reason) = error {
                phase = .unavailable(reason)
            } else {
                phase = .idle
            }
        }
    }
}
