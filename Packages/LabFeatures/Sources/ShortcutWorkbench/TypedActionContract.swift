import Foundation

/// One typed action contract the workbench publishes: either a curated App Shortcut entry, or a
/// pointer into the larger atomic Action Atlas library.
///
/// Curated entries are the small set Shortcuts promotes (at most ten). Atomic contracts name the
/// full library without claiming App Shortcut packaging.
public struct TypedActionContract: Hashable, Sendable, Identifiable, Codable {
    public enum Layer: String, Hashable, Sendable, Codable, CaseIterable {
        /// Promoted through `AppShortcutsProvider`. At most `ShortcutWorkbench.curatedShortcutCap`.
        case curated
        /// Discoverable in the Shortcuts action library and the in-app action browser.
        case atomic
    }

    public enum Mutation: String, Hashable, Sendable, Codable, CaseIterable {
        case readOnly
        case commitOnce
        case destructiveConfirm
    }

    public let id: String
    public let title: String
    public let layer: Layer
    public let mutation: Mutation
    /// One sentence for the workbench browser and manual recipe cards.
    public let summary: String

    public init(id: String, title: String, layer: Layer, mutation: Mutation, summary: String) {
        self.id = id
        self.title = title
        self.layer = layer
        self.mutation = mutation
        self.summary = summary
    }

    /// The curated set this build declares. Kept under the App Shortcuts cap and separate from the
    /// atomic library titles Action Atlas already exposes.
    public static let curated: [TypedActionContract] = [
        TypedActionContract(
            id: "open-workbench",
            title: "Open Shortcut Workbench",
            layer: .curated,
            mutation: .readOnly,
            summary: "Opens the workbench so you can walk a recipe without building a shortcut first."
        ),
        TypedActionContract(
            id: "run-import-export-recipe",
            title: "Run Import–Export Recipe",
            layer: .curated,
            mutation: .commitOnce,
            summary: "Walks import → query → transform → export on the recipe's stable item references."
        ),
        TypedActionContract(
            id: "resolve-lab-item",
            title: "Resolve Lab Item",
            layer: .curated,
            mutation: .readOnly,
            summary: "Looks up a lab item by its stable identifier, so a rename does not break the shortcut."
        ),
        TypedActionContract(
            id: "inspect-model-step",
            title: "Inspect Model Step",
            layer: .curated,
            mutation: .readOnly,
            summary: "Shows what an optional model step would receive, with secret-shaped fields redacted."
        ),
        TypedActionContract(
            id: "export-recipe",
            title: "Export Recipe",
            layer: .curated,
            mutation: .readOnly,
            summary: "Exports a recipe definition. Raw secret values never appear in the file."
        ),
        TypedActionContract(
            id: "find-lab-items",
            title: "Find Lab Items",
            layer: .curated,
            mutation: .readOnly,
            summary: "The Action Atlas find action, also offered as a curated entry for common recipes."
        ),
    ]

    /// Representative atomic contracts. The full Action Atlas library is larger; these document the
    /// boundary between curated promotion and the discoverable library.
    public static let atomicSamples: [TypedActionContract] = [
        TypedActionContract(
            id: "create-lab-item",
            title: "Create Lab Item",
            layer: .atomic,
            mutation: .commitOnce,
            summary: "Creates an item in one of your collections. Available in the action library, not as a curated App Shortcut."
        ),
        TypedActionContract(
            id: "archive-lab-item",
            title: "Archive Lab Item",
            layer: .atomic,
            mutation: .destructiveConfirm,
            summary: "Archives an item after system confirmation. Atomic library only."
        ),
        TypedActionContract(
            id: "export-lab-item",
            title: "Export Lab Item",
            layer: .atomic,
            mutation: .readOnly,
            summary: "Exports one item as a portable document. Atomic library only."
        ),
    ]

    public static var allPublished: [TypedActionContract] { curated + atomicSamples }
}
