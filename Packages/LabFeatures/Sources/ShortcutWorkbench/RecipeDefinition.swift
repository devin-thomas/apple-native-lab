import Foundation
import LabDomain

/// One step in an import → query → transform → export recipe.
public enum RecipeStepKind: String, Hashable, Sendable, Codable, CaseIterable {
    case importDocument = "import"
    case query
    case transform
    case export
}

/// A named step with the small payload the walkthrough needs. Entity identity always lives on the
/// recipe itself (`sourceItemIDs`), never as a display title inside a step.
public struct RecipeStep: Hashable, Sendable, Codable, Identifiable {
    public var id: String { "\(kind.rawValue)-\(order)" }
    public let order: Int
    public let kind: RecipeStepKind
    /// For `.query`: the text to match. For `.transform`: optional note suffix to append.
    public let detail: String?

    public init(order: Int, kind: RecipeStepKind, detail: String? = nil) {
        self.order = order
        self.kind = kind
        self.detail = detail
    }
}

/// Optional fields a model step would receive. Inspected in-app; never stored as Shortcuts secrets.
public struct ModelStepPayload: Hashable, Sendable, Codable {
    /// Free-form fields a recipe author attached. In-app inspection masks secret-shaped names;
    /// exports withhold every typed name and value (`RecipeExport`).
    public var fields: [String: String]

    public init(fields: [String: String] = [:]) {
        self.fields = fields
    }
}

/// A typed automation recipe: curated walkthroughs that bind stable entity references.
///
/// Renaming a source item leaves its UUID unchanged, so the recipe still resolves. Deletion yields
/// a recoverable missing-item result rather than a silent empty run.
public struct RecipeDefinition: Hashable, Sendable, Codable, Identifiable {
    public static let format = "native-lab-recipe"
    /// Version 2 (LAB-003-B repair): exports carry only lab-authored text and mark the rest
    /// `[withheld]`.
    public static let formatVersion = 2

    public let id: RecipeID
    public var title: String
    public var steps: [RecipeStep]
    /// Stable item identifiers the recipe binds. Titles are never primary keys.
    public var sourceItemIDs: [ItemID]
    public var modelStep: ModelStepPayload?

    public init(
        id: RecipeID = RecipeID(),
        title: String,
        steps: [RecipeStep],
        sourceItemIDs: [ItemID] = [],
        modelStep: ModelStepPayload? = nil
    ) {
        self.id = id
        self.title = title
        self.steps = steps.sorted { $0.order < $1.order }
        self.sourceItemIDs = sourceItemIDs
        self.modelStep = modelStep
    }

    /// The built-in import → query → transform → export walkthrough.
    public static func importExportWalkthrough(
        id: RecipeID = RecipeID(rawValue: UUID(uuidString: "A3C00300-0001-4000-8000-000000000001")!),
        sourceItemIDs: [ItemID] = [],
        query: String = "sample",
        transformNote: String = " · recipe transform"
    ) -> RecipeDefinition {
        RecipeDefinition(
            id: id,
            title: "Import → Query → Transform → Export",
            steps: [
                RecipeStep(order: 1, kind: .importDocument),
                RecipeStep(order: 2, kind: .query, detail: query),
                RecipeStep(order: 3, kind: .transform, detail: transformNote),
                RecipeStep(order: 4, kind: .export),
            ],
            sourceItemIDs: sourceItemIDs
        )
    }
}
