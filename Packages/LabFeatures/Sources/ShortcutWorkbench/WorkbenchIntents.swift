import ActionAtlas
import AppIntents
import Foundation
import LabDomain

/// What a workbench intent returns besides its typed value.
public struct WorkbenchIntentOutput<Value: Sendable>: Sendable {
    public let value: Value
    public let dialog: String
    public let receipt: ActionReceipt?

    init(value: Value, dialog: String, receipt: ActionReceipt? = nil) {
        self.value = value
        self.dialog = dialog
        self.receipt = receipt
    }
}

// MARK: - Open

/// Destinations the Open Shortcut Workbench intent can open.
public enum ShortcutWorkbenchDestination: String, AppEnum {
    case workbench

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Destination"
    public static let caseDisplayRepresentations: [ShortcutWorkbenchDestination: DisplayRepresentation] = [
        .workbench: "Shortcut Workbench",
    ]
}

/// Brings Native Lab forward on the Shortcut Workbench. Curated App Shortcut entry.
public struct OpenShortcutWorkbenchIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Shortcut Workbench"
    public static let description = IntentDescription(
        "Opens Native Lab's Shortcut Workbench: curated recipes, manual instructions, and the action browser."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    public static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Destination", default: .workbench)
    public var target: ShortcutWorkbenchDestination

    @Dependency(default: WorkbenchLink.unavailable) private var workbench: WorkbenchLink

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await workbench.open()
        return .result(dialog: "Opening Shortcut Workbench in Native Lab.")
    }
}

// MARK: - Resolve (rename-safe)

public struct ResolveLabItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Resolve Lab Item"
    public static let description = IntentDescription(
        "Looks up a lab item by its stable identifier. Renaming the item does not change the identifier, so a recipe that stored it still finds the item."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Item")
    public var item: LabItemEntity

    @Dependency(default: WorkbenchLink.unavailable) private var workbench: WorkbenchLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Resolve \(\.$item)")
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<LabItemEntity> & ProvidesDialog {
        let output = try await run(with: workbench)
        return .result(value: output.value, dialog: "\(output.dialog)")
    }

    public func run(with link: WorkbenchLink) async throws(WorkbenchError) -> WorkbenchIntentOutput<LabItemEntity> {
        let actions = link.actions(.appIntent)
        let resolved = try await actions.resolveItem(item.itemID)
        let titles = try await collectionTitle(for: resolved, actions: actions)
        let entity = LabItemEntity(resolved, collectionTitle: titles)
        return WorkbenchIntentOutput(
            value: entity,
            dialog: "Resolved “\(resolved.title.value)” (revision \(resolved.revision.rawValue)). Its identifier is unchanged if you rename it."
        )
    }

    private func collectionTitle(for item: LabItem, actions: WorkbenchActions) async throws(WorkbenchError) -> String {
        do {
            return try await actions.backend.collection(item.collectionID, via: .appIntent).title.value
        } catch {
            return ""
        }
    }
}

// MARK: - Inspect model step

public struct InspectModelStepIntent: AppIntent {
    public static let title: LocalizedStringResource = "Inspect Model Step"
    public static let description = IntentDescription(
        "Shows what an optional model step would receive. Secret-shaped fields are redacted and are never stored in Shortcuts."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Recipe ID", description: "The recipe's UUID. Leave empty to inspect the bundled Query → Report recipe.")
    public var recipeID: String?

    @Dependency(default: WorkbenchLink.unavailable) private var workbench: WorkbenchLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Inspect model step of recipe \(\.$recipeID)")
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let output = try await run(with: workbench)
        return .result(value: output.value, dialog: "\(output.dialog)")
    }

    public func run(with link: WorkbenchLink) async throws(WorkbenchError) -> WorkbenchIntentOutput<String> {
        let actions = link.actions(.appIntent)
        let recipe: RecipeDefinition
        if let text = recipeID?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            guard let uuid = UUID(uuidString: text) else { throw .invalidRequestID }
            recipe = try actions.recipe(RecipeID(rawValue: uuid))
        } else {
            recipe = try actions.recipe(RecipeID(rawValue: UUID(uuidString: "A3C00300-0001-4000-8000-000000000002")!))
        }
        let inspection = try actions.inspectModelStep(of: recipe)
        let lines = inspection.fields.keys.sorted().map { "\($0): \(inspection.fields[$0] ?? "")" }
        let body = ([inspection.summary] + lines).joined(separator: "\n")
        return WorkbenchIntentOutput(value: body, dialog: inspection.summary)
    }
}

// MARK: - Export recipe

public struct ExportRecipeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Export Recipe"
    public static let description = IntentDescription(
        "Exports a recipe definition as JSON. Raw secret values never appear in the file."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Recipe ID", description: "Leave empty for the Import → Export walkthrough.")
    public var recipeID: String?

    @Dependency(default: WorkbenchLink.unavailable) private var workbench: WorkbenchLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Export recipe \(\.$recipeID)")
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let output = try await run(with: workbench)
        let file = IntentFile(data: output.value.data, filename: output.value.filename, type: .json)
        let dialog: String
        if output.value.redactedKeys.isEmpty {
            dialog = "Exported “\(output.value.recipe.title)”."
        } else {
            dialog = "Exported “\(output.value.recipe.title)”. Secret-shaped fields (\(output.value.redactedKeys.joined(separator: ", "))) were written as \(SecretRedaction.placeholder)."
        }
        return .result(value: file, dialog: "\(dialog)")
    }

    public func run(with link: WorkbenchLink) async throws(WorkbenchError) -> WorkbenchIntentOutput<RecipeExport> {
        let actions = link.actions(.appIntent)
        let recipe: RecipeDefinition
        if let text = recipeID?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            guard let uuid = UUID(uuidString: text) else { throw .invalidRequestID }
            recipe = try actions.recipe(RecipeID(rawValue: uuid))
        } else {
            recipe = try actions.recipe(RecipeDefinition.importExportWalkthrough().id)
        }
        return WorkbenchIntentOutput(value: actions.exportRecipe(recipe), dialog: "Exported.")
    }
}

// MARK: - Run recipe

public struct RunImportExportRecipeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Import–Export Recipe"
    public static let description = IntentDescription(
        "Walks the Import → Query → Transform → Export recipe on a bound lab item, or creates one in the collection you choose."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(
        title: "Collection",
        description: "One of your own collections for a new import step."
    )
    public var collection: LabCollectionEntity?

    @Parameter(title: "Source Item", description: "Optional. Bind this stable item reference; renaming it will not break the recipe.")
    public var sourceItem: LabItemEntity?

    @Parameter(title: "Import Title", description: "Used when the recipe creates an item.")
    public var importTitle: String?

    @Parameter(title: "Request ID", description: "Optional. Running again with the same request ID returns the first import result.")
    public var requestID: String?

    @Dependency(default: WorkbenchLink.unavailable) private var workbench: WorkbenchLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Run import–export recipe into \(\.$collection)") {
            \.$sourceItem
            \.$importTitle
            \.$requestID
        }
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let output = try await run(with: workbench)
        return .result(value: output.value, dialog: "\(output.dialog)")
    }

    public func run(
        with link: WorkbenchLink,
        staging: RecipeImportStaging = RecipeImportStaging()
    ) async throws -> WorkbenchIntentOutput<String> {
        let actions = link.actions(.appIntent)
        var recipe = try actions.recipe(RecipeDefinition.importExportWalkthrough().id)
        if let sourceItem {
            recipe.sourceItemIDs = [sourceItem.itemID]
            // Drop the import step when a source is already bound: query/transform/export only.
            recipe.steps = recipe.steps.filter { $0.kind != .importDocument }
            actions.saveRecipe(recipe)
        }
        let collectionID = collection?.collectionID
        let result = try await actions.runRecipe(
            recipe,
            importTitle: importTitle,
            into: collectionID,
            request: try WorkbenchRequest(text: requestID),
            staging: staging
        )
        return WorkbenchIntentOutput(value: result.job.summary, dialog: result.job.summary, receipt: result.transformReceipt ?? result.importReceipt)
    }
}

// MARK: - Package and curated App Shortcuts

public struct ShortcutWorkbenchIntentsPackage: AppIntentsPackage {}

/// Curated App Shortcuts (≤10). Separate from Action Atlas's atomic library ([S03]).
public struct NativeLabAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenShortcutWorkbenchIntent(),
            phrases: [
                "Open Shortcut Workbench in \(.applicationName)",
                "Show Shortcut Workbench in \(.applicationName)",
            ],
            shortTitle: "Workbench",
            systemImageName: "hammer"
        )
        AppShortcut(
            intent: RunImportExportRecipeIntent(),
            phrases: [
                "Run the import export recipe in \(.applicationName)",
                "Run a lab recipe in \(.applicationName)",
            ],
            shortTitle: "Run Recipe",
            systemImageName: "list.bullet.rectangle"
        )
        AppShortcut(
            intent: ResolveLabItemIntent(),
            phrases: [
                "Resolve a lab item in \(.applicationName)",
            ],
            shortTitle: "Resolve Item",
            systemImageName: "link"
        )
        AppShortcut(
            intent: InspectModelStepIntent(),
            phrases: [
                "Inspect a model step in \(.applicationName)",
            ],
            shortTitle: "Inspect Model",
            systemImageName: "eye"
        )
        AppShortcut(
            intent: ExportRecipeIntent(),
            phrases: [
                "Export a lab recipe in \(.applicationName)",
            ],
            shortTitle: "Export Recipe",
            systemImageName: "square.and.arrow.up"
        )
        AppShortcut(
            intent: FindItemsIntent(),
            phrases: [
                "Find lab items in \(.applicationName)",
            ],
            shortTitle: "Find Items",
            systemImageName: "magnifyingglass"
        )
    }
}
