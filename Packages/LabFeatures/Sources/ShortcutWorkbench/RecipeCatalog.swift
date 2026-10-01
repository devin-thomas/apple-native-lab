import Foundation
import Synchronization

/// Process-wide recipe catalog. Demo recipes are seeded; person-authored recipes persist for the
/// session only (Reset Demo does not remove them — they are not demo-namespace store entities).
public final class WorkbenchRecipeCatalog: Sendable {
    public static let shared = WorkbenchRecipeCatalog()

    private let lock = Mutex<[RecipeID: RecipeDefinition]>([:])

    public init(seed: [RecipeDefinition] = WorkbenchRecipeCatalog.bundledRecipes) {
        lock.withLock { store in
            for recipe in seed { store[recipe.id] = recipe }
        }
    }

    public func all() -> [RecipeDefinition] {
        lock.withLock { $0.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    }

    public func recipe(_ id: RecipeID) -> RecipeDefinition? {
        lock.withLock { $0[id] }
    }

    public func save(_ recipe: RecipeDefinition) {
        lock.withLock { $0[recipe.id] = recipe }
    }

    public func remove(_ id: RecipeID) {
        lock.withLock { _ = $0.removeValue(forKey: id) }
    }

    /// Clears person-authored recipes and restores the bundled set. Used by tests.
    public func resetToBundled() {
        lock.withLock { store in
            store = [:]
            for recipe in Self.bundledRecipes { store[recipe.id] = recipe }
        }
    }

    public static let bundledRecipes: [RecipeDefinition] = [
        RecipeDefinition.importExportWalkthrough(),
        RecipeDefinition(
            id: RecipeID(rawValue: UUID(uuidString: "A3C00300-0001-4000-8000-000000000002")!),
            title: "Query → Report",
            steps: [
                RecipeStep(order: 1, kind: .query, detail: "amber"),
                RecipeStep(order: 2, kind: .export),
            ],
            sourceItemIDs: [],
            modelStep: ModelStepPayload(fields: [
                "prompt": "Summarize matching lab items.",
                "tone": "neutral",
            ])
        ),
    ]
}

/// Holds staged import drafts in memory. Cancel removes the draft so a half import never commits.
public actor RecipeImportStaging {
    private var drafts: [UUID: RecipeImportDraft] = [:]

    public init() {}

    public func begin(title: String, note: String) throws(WorkbenchError) -> RecipeImportDraft {
        let token = UUID()
        let payload = "\(title)\n\(note)"
        let draft = RecipeImportDraft(
            stagingToken: token,
            title: title,
            note: note,
            byteCount: payload.utf8.count
        )
        drafts[token] = draft
        return draft
    }

    public func has(_ token: UUID) -> Bool { drafts[token] != nil }

    public func cancel(_ token: UUID) {
        drafts.removeValue(forKey: token)
    }

    public func finish(_ token: UUID) {
        drafts.removeValue(forKey: token)
    }

    public var pendingCount: Int { drafts.count }
}
