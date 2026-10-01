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
        guard !Task.isCancelled else {
            await staging.cancel(draft.stagingToken)
            throw .cancelled
        }
        guard await staging.has(draft.stagingToken) else {
            throw .importIncomplete(reason: "That import was cancelled or already finished.")
        }
        let parent = try await backend.collection(collectionID, via: entryPoint)
        let title: EntityTitle
        let note: ItemNote
        do {
            title = try EntityTitle(draft.title)
            note = try ItemNote(draft.note)
        } catch {
            await staging.cancel(draft.stagingToken)
            throw .invalidInput("The staged title or note is not valid.")
        }
        let draftItem = ItemDraft(id: request.newItemID, in: parent.id, title: title, note: note)
        let receipt = try await commit(
            .createItem(draft: draftItem),
            request: request,
            names: [.item(draftItem.id): title.value, .collection(parent.id): parent.title.value]
        )
        await staging.finish(draft.stagingToken)
        return WorkbenchOutcome(receipt: receipt, entity: try await resolveItem(draftItem.id))
    }

    // MARK: Recipe run

    /// Walks the recipe's steps. Import uses `staging`; a cancel mid-import discards the draft and
    /// commits nothing. Query and resolve use stable IDs. Transform updates through the service.
    /// Export returns a redacted `RecipeExport`.
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
        var importReceipt: ActionReceipt?
        var transformReceipt: ActionReceipt?
        var matched: [LabItem] = []
        var export: RecipeExport?

        for step in recipe.steps {
            guard !Task.isCancelled else {
                job.state = .cancelled
                job.summary = WorkbenchError.cancelled.message
                return RecipeRunResult(job: job, importReceipt: importReceipt, transformReceipt: transformReceipt, matched: matched, export: export)
            }
            switch step.kind {
            case .importDocument:
                guard let collectionID else {
                    throw .invalidInput("This recipe's import step needs one of your collections.")
                }
                let draft = try await beginImport(
                    title: importTitle ?? "Recipe import",
                    note: importNote,
                    into: collectionID,
                    staging: staging
                )
                if Task.isCancelled {
                    await cancelImport(draft, staging: staging)
                    job.state = .cancelled
                    job.summary = WorkbenchError.cancelled.message
                    return RecipeRunResult(job: job, importReceipt: nil, transformReceipt: nil, matched: [], export: nil)
                }
                let outcome = try await commitImport(draft, into: collectionID, request: request, staging: staging)
                importReceipt = outcome.receipt
                // Bind the new item so later steps and future runs resolve by ID after a rename.
                var bound = recipe
                if !bound.sourceItemIDs.contains(outcome.entity.id) {
                    bound.sourceItemIDs.append(outcome.entity.id)
                    catalog.save(bound)
                }
            case .query:
                let text = step.detail
                let filter: ItemFilter
                do {
                    filter = try ItemFilter(text: text, includeArchived: false, limit: 50)
                } catch {
                    throw .invalidInput("The query text is not valid.")
                }
                matched = try await backend.items(filter, via: entryPoint)
                // Prefer recipe-bound sources when present: prove rename survival.
                if !recipe.sourceItemIDs.isEmpty {
                    matched = try await resolveSources(of: recipe)
                }
            case .transform:
                let sources = try await resolveSources(of: recipe)
                guard let first = sources.first else {
                    throw .invalidInput("This recipe has no source item to transform.")
                }
                let suffix = step.detail ?? ""
                let newNote = first.note.value + suffix
                let changes: ItemChanges
                do {
                    changes = try ItemChanges(note: try ItemNote(newNote))
                } catch {
                    throw .invalidInput("The transformed note is not valid.")
                }
                let transformRequest = WorkbenchRequest(RequestID())
                let receipt = try await commit(
                    .updateItem(id: first.id, expected: first.revision, changes: changes),
                    request: transformRequest,
                    names: [.item(first.id): first.title.value]
                )
                transformReceipt = receipt
                matched = [try await resolveItem(first.id)]
            case .export:
                export = exportRecipe(catalog.recipe(recipe.id) ?? recipe)
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

/// The outcome of one recipe walkthrough.
public struct RecipeRunResult: Sendable {
    public let job: JobHandle
    public let importReceipt: ActionReceipt?
    public let transformReceipt: ActionReceipt?
    public let matched: [LabItem]
    public let export: RecipeExport?
}
