import Foundation
import LabDomain

/// One requested workbench decision, reused on retry.
public struct WorkbenchRequest: Hashable, Sendable {
    public let id: RequestID

    public init(_ id: RequestID = RequestID()) { self.id = id }

    public init(text: String?) throws(WorkbenchError) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            self.init()
            return
        }
        guard let uuid = UUID(uuidString: trimmed) else { throw .invalidRequestID }
        self.init(RequestID(rawValue: uuid))
    }

    public var newItemID: ItemID { ItemID(rawValue: derived(salt: 0x5A)) }
    public var newCollectionID: CollectionID { CollectionID(rawValue: derived(salt: 0xC3)) }

    private func derived(salt: UInt8) -> UUID {
        var bytes = id.rawValue.uuid
        withUnsafeMutableBytes(of: &bytes) { raw in
            for index in raw.indices {
                switch index {
                case 6: raw[index] ^= salt & 0x0F
                case 8: raw[index] ^= salt & 0x3F
                default: raw[index] ^= salt
                }
            }
        }
        return UUID(uuid: bytes)
    }
}

/// A committed change and the entity it left.
public struct WorkbenchOutcome<Entity: Sendable>: Sendable {
    public let receipt: ActionReceipt
    public let entity: Entity
}

/// In-flight import state. Cancel discards staging and commits nothing.
public struct RecipeImportDraft: Hashable, Sendable {
    public let stagingToken: UUID
    public let title: String
    public let note: String
    public let byteCount: Int

    public init(stagingToken: UUID, title: String, note: String, byteCount: Int) {
        self.stagingToken = stagingToken
        self.title = title
        self.note = note
        self.byteCount = byteCount
    }
}

/// The workbench action library both the in-app UI and App Intents call.
public struct WorkbenchActions: Sendable {
    public let backend: any WorkbenchBackend
    public let entryPoint: WorkbenchEntryPoint
    /// Recipe catalog for this process. Hosts and tests share one via `WorkbenchRecipeCatalog.shared`.
    public let catalog: WorkbenchRecipeCatalog

    public init(
        backend: any WorkbenchBackend,
        entryPoint: WorkbenchEntryPoint,
        catalog: WorkbenchRecipeCatalog = .shared
    ) {
        self.backend = backend
        self.entryPoint = entryPoint
        self.catalog = catalog
    }

    // MARK: Catalog and contracts

    public func curatedContracts() -> [TypedActionContract] { TypedActionContract.curated }

    public func atomicSampleContracts() -> [TypedActionContract] { TypedActionContract.atomicSamples }

    public func recipes() -> [RecipeDefinition] { catalog.all() }

    public func recipe(_ id: RecipeID) throws(WorkbenchError) -> RecipeDefinition {
        guard let recipe = catalog.recipe(id) else { throw .missingRecipe(id) }
        return recipe
    }

    /// Registers or replaces a recipe the person authored. Fixtures and Reset Demo do not touch these.
    public func saveRecipe(_ recipe: RecipeDefinition) {
        catalog.save(recipe)
    }

    // MARK: Entity resolution (rename-safe)

    /// Resolves a stored item by stable ID. A rename of its title leaves the ID unchanged.
    public func resolveItem(_ id: ItemID) async throws(WorkbenchError) -> LabItem {
        try await backend.item(id, via: entryPoint)
    }

    /// Resolves every source item on a recipe. Missing IDs throw rather than silently skipping, so
    /// a deleted entity is recoverable and visible.
    public func resolveSources(of recipe: RecipeDefinition) async throws(WorkbenchError) -> [LabItem] {
        var items: [LabItem] = []
        for id in recipe.sourceItemIDs {
            items.append(try await resolveItem(id))
        }
        return items
    }

    // MARK: Model step inspection

    public func inspectModelStep(_ payload: ModelStepPayload) -> ModelStepInspection {
        ModelStepInspection(payload: payload)
    }

    public func inspectModelStep(of recipe: RecipeDefinition) throws(WorkbenchError) -> ModelStepInspection {
        guard let payload = recipe.modelStep else {
            throw .invalidInput("This recipe has no model step to inspect.")
        }
        return inspectModelStep(payload)
    }

    // MARK: Export (never raw secrets)

    public func exportRecipe(_ recipe: RecipeDefinition) -> RecipeExport {
        RecipeExport(recipe: recipe)
    }

    public func exportRecipe(id: RecipeID) throws(WorkbenchError) -> RecipeExport {
        exportRecipe(try recipe(id))
    }

    // MARK: Import with cancellation

    /// Stages a simple text import into a draft. Nothing is committed until `commitImport`.
    /// Cancel via `cancelImport` so a half import never reaches the store.
    public func beginImport(
        title: String,
        note: String = "",
        into collectionID: CollectionID,
        staging: RecipeImportStaging
    ) async throws(WorkbenchError) -> RecipeImportDraft {
        guard !Task.isCancelled else { throw .cancelled }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw .invalidInput("A title cannot be empty.") }
        // Prove the collection exists before staging.
        _ = try await backend.collection(collectionID, via: entryPoint)
        return try await staging.begin(title: trimmedTitle, note: note)
    }

    public func cancelImport(_ draft: RecipeImportDraft, staging: RecipeImportStaging) async {
        await staging.cancel(draft.stagingToken)
    }

    /// Commits a staged import as one `createItem` through the operation service.
    public func commitImport(
        _ draft: RecipeImportDraft,
        into collectionID: CollectionID,
        request: WorkbenchRequest,
        staging: RecipeImportStaging
    ) async throws(WorkbenchError) -> WorkbenchOutcome<LabItem> {
        let receipt = try await commitStaged(draft, note: draft.note, into: collectionID, request: request, staging: staging)
        return WorkbenchOutcome(receipt: receipt, entity: try await resolveItem(request.newItemID))
    }

    /// The one commit behind `commitImport` and a recipe run's import: a `createItem` for the
    /// staged title with `note`. The draft is finished on success and discarded on any failure,
    /// so staging never holds a draft whose commit was refused.
    private func commitStaged(
        _ draft: RecipeImportDraft,
        note noteText: String,
        into collectionID: CollectionID,
        request: WorkbenchRequest,
        staging: RecipeImportStaging
    ) async throws(WorkbenchError) -> ActionReceipt {
        guard !Task.isCancelled else {
            await staging.cancel(draft.stagingToken)
            throw .cancelled
        }
        guard await staging.has(draft.stagingToken) else {
            throw .importIncomplete(reason: "That import was cancelled or already finished.")
        }
        do throws(WorkbenchError) {
            let parent = try await backend.collection(collectionID, via: entryPoint)
            let title: EntityTitle
            let note: ItemNote
            do {
                title = try EntityTitle(draft.title)
                note = try ItemNote(noteText)
            } catch {
                throw WorkbenchError.invalidInput("The staged title or note is not valid.")
            }
            let draftItem = ItemDraft(id: request.newItemID, in: parent.id, title: title, note: note)
            let receipt = try await commit(
                .createItem(draft: draftItem),
                request: request,
                names: [.item(draftItem.id): title.value, .collection(parent.id): parent.title.value]
            )
            await staging.finish(draft.stagingToken)
            return receipt
        } catch {
            await staging.cancel(draft.stagingToken)
            throw error
        }
    }

    // MARK: Recipe run

    /// Walks the recipe's steps, committing at most one operation, and only after every step has
    /// been checked.
    ///
    /// A run is planned in full before it changes anything: the import's collection, title, and
    /// note; each query; the transform's source and resulting note; and the step order. A recipe
    /// that cannot complete is refused there, with nothing staged or committed. A recipe that
    /// imports transforms the item it imports, so the transform is folded into the import's one
    /// `createItem`; the new item is then bound as the recipe's source. A recipe without an import
    /// transforms its first bound source with one `updateItem`. Either way the run's change is
    /// atomic: all of it commits, or none of it does. Cancelling before that commit discards the
    /// staged draft; after it, the remaining steps only read and export.
    public func runRecipe(
        _ recipe: RecipeDefinition,
        importTitle: String? = nil,
        importNote: String = "",
        into collectionID: CollectionID?,
        request: WorkbenchRequest,
        staging: RecipeImportStaging
    ) async throws(WorkbenchError) -> RecipeRunResult {
        var job = JobHandle(
            recipeID: recipe.id,
            kind: "recipe-run",
            state: .running,
            totalUnits: recipe.steps.count,
            summary: "Running “\(recipe.title)”…"
        )
        func cancelled() -> RecipeRunResult {
            job.state = .cancelled
            job.summary = WorkbenchError.cancelled.message
            return RecipeRunResult(job: job, importReceipt: nil, transformReceipt: nil, matched: [], export: nil)
        }
        guard !Task.isCancelled else { return cancelled() }

        let plan = try await planRun(recipe, importTitle: importTitle, importNote: importNote, into: collectionID)
        var running = recipe
        var committed = false
        var importReceipt: ActionReceipt?
        var transformReceipt: ActionReceipt?
        var matched: [LabItem] = []
        var export: RecipeExport?

        for step in recipe.steps {
            // Once the run's one commit has happened, it finishes: the rest only reads.
            if !committed, Task.isCancelled { return cancelled() }
            switch step.kind {
            case .importDocument:
                guard let importing = plan.importing else { break }
                let draft = try await staging.begin(title: importing.title, note: importNote)
                if Task.isCancelled {
                    await cancelImport(draft, staging: staging)
                    return cancelled()
                }
                let receipt = try await commitStaged(
                    draft,
                    note: importing.committedNote,
                    into: importing.collectionID,
                    request: request,
                    staging: staging
                )
                committed = true
                importReceipt = receipt
                if plan.transformsImport { transformReceipt = receipt }
                // Bind the new item before anything else can fail, so the store and the recipe
                // agree even if a later read does not: later steps and future runs resolve it by ID.
                running.sourceItemIDs = [request.newItemID]
                catalog.save(running)
            case .query:
                if running.sourceItemIDs.isEmpty, let filter = plan.queries[step.order] {
                    matched = try await backend.items(filter, via: entryPoint)
                } else {
                    // Prefer recipe-bound sources: proves rename survival.
                    matched = try await resolveSources(of: running)
                }
            case .transform:
                if plan.transformsImport {
                    // Already applied by the import's commit; report the item it left.
                    matched = [try await resolveItem(request.newItemID)]
                } else if let bound = plan.boundTransform, transformReceipt != nil {
                    // Every transform suffix rode on the first transform step's one commit.
                    matched = [try await resolveItem(bound.source.id)]
                } else if let bound = plan.boundTransform {
                    let receipt = try await commit(
                        .updateItem(id: bound.source.id, expected: bound.source.revision, changes: bound.changes),
                        request: WorkbenchRequest(RequestID()),
                        names: [.item(bound.source.id): bound.source.title.value]
                    )
                    committed = true
                    transformReceipt = receipt
                    matched = [try await resolveItem(bound.source.id)]
                }
            case .export:
                export = exportRecipe(running)
            }
            job.completedUnits += 1
            job.checkpoint = step.order
        }

        job.state = .completed
        job.summary = "Finished “\(recipe.title)”."
        return RecipeRunResult(
            job: job,
            importReceipt: importReceipt,
            transformReceipt: transformReceipt,
            matched: matched,
            export: export
        )
    }

    /// Checks every step of a run before anything is staged or committed. Each refusal leaves the
    /// store, staging, and catalog exactly as they were.
    func planRun(
        _ recipe: RecipeDefinition,
        importTitle: String?,
        importNote: String,
        into collectionID: CollectionID?
    ) async throws(WorkbenchError) -> RecipeRunPlan {
        let imports = recipe.steps.filter { $0.kind == .importDocument }
        let transforms = recipe.steps.filter { $0.kind == .transform }
        guard imports.count <= 1 else {
            throw .invalidInput("A recipe can import at most one item.")
        }
        let suffix = transforms.map { $0.detail ?? "" }.joined()

        var queries: [Int: ItemFilter] = [:]
        for step in recipe.steps where step.kind == .query {
            do {
                queries[step.order] = try ItemFilter(text: step.detail, includeArchived: false, limit: 50)
            } catch {
                throw .invalidInput("The query text in step \(step.order) is not valid.")
            }
        }

        if let importStep = imports.first {
            guard let collectionID else {
                throw .invalidInput("This recipe's import step needs one of your collections.")
            }
            if let early = transforms.first(where: { $0.order < importStep.order }) {
                throw .invalidInput("Step \(early.order) transforms before the recipe imports its item. Move the transform after the import.")
            }
            let title = (importTitle ?? "Recipe import").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw .invalidInput("A title cannot be empty.") }
            do {
                _ = try EntityTitle(title)
            } catch {
                throw .invalidInput("The import title is not valid.")
            }
            let committedNote = importNote + suffix
            do {
                _ = try ItemNote(committedNote)
            } catch {
                throw .invalidInput(transforms.isEmpty ? "The import note is not valid." : "The transformed note is not valid.")
            }
            // Prove the collection exists before staging.
            _ = try await backend.collection(collectionID, via: entryPoint)
            return RecipeRunPlan(
                importing: .init(collectionID: collectionID, title: title, committedNote: committedNote),
                transformsImport: !transforms.isEmpty,
                boundTransform: nil,
                queries: queries
            )
        }

        guard !transforms.isEmpty else {
            return RecipeRunPlan(importing: nil, transformsImport: false, boundTransform: nil, queries: queries)
        }
        let sources = try await resolveSources(of: recipe)
        guard let first = sources.first else {
            throw .invalidInput("This recipe has no source item to transform. Bind an item, or add an import step before the transform.")
        }
        let changes: ItemChanges
        do {
            changes = try ItemChanges(note: try ItemNote(first.note.value + suffix))
        } catch {
            throw .invalidInput("The transformed note is not valid.")
        }
        return RecipeRunPlan(
            importing: nil,
            transformsImport: false,
            boundTransform: .init(source: first, changes: changes),
            queries: queries
        )
    }

    // MARK: Collection helpers

    public func collectionsOfYourOwn() async throws(WorkbenchError) -> [LabCollection] {
        try await backend.collections(via: entryPoint).filter { !$0.isArchived && $0.namespace == .user }
    }

    // MARK: Internals

    private var routineAuthority: WorkbenchAuthority {
        switch entryPoint {
        case .appUI: .appControl
        case .appIntent: .intent
        }
    }

    private func commit(
        _ operation: DomainOperation,
        request: WorkbenchRequest,
        names: [EntityReference: String]
    ) async throws(WorkbenchError) -> ActionReceipt {
        guard !Task.isCancelled else { throw .cancelled }
        let receipt = try await backend.commit(operation, requestID: request.id, authority: routineAuthority, names: names)
        if let conflict = receipt.conflict { throw .conflict(conflict) }
        return receipt
    }
}

/// What a recipe run will do, fixed before it stages or commits anything.
struct RecipeRunPlan: Sendable {
    struct Import: Sendable {
        let collectionID: CollectionID
        let title: String
        /// The imported note with every transform suffix already applied.
        let committedNote: String
    }

    struct BoundTransform: Sendable {
        let source: LabItem
        let changes: ItemChanges
    }

    let importing: Import?
    /// The transform rides on the import's commit.
    let transformsImport: Bool
    let boundTransform: BoundTransform?
    let queries: [Int: ItemFilter]
}

/// The outcome of one recipe walkthrough. A run commits at most one operation; when it imports
/// and transforms, `importReceipt` and `transformReceipt` are that same commit.
public struct RecipeRunResult: Sendable {
    public let job: JobHandle
    public let importReceipt: ActionReceipt?
    public let transformReceipt: ActionReceipt?
    public let matched: [LabItem]
    public let export: RecipeExport?
}
