import Foundation
import LabDomain

/// A committed change and the state it left, read back through the service.
public struct AtlasOutcome<Entity: Sendable>: Sendable {
    public let receipt: ActionReceipt
    public let entity: Entity
}

/// What the person is asked before an archive commits.
public struct ArchivePrompt: Hashable, Sendable {
    public let itemTitle: String
    /// One sentence naming the change and saying it can be undone.
    public let text: String
}

/// How several candidates become one choice: the system's disambiguation for an App Intent, or a
/// picker in the app. It throws when the person declines to choose.
public typealias AtlasChooser<Value> = @Sendable ([Value]) async throws -> Value

/// The action library that the in-app action browser and every App Intent call.
///
/// Each action validates its input, reads and commits through the host's `ActionAtlasBackend`,
/// and so through the same `OperationService` path for both entry points. Only the adapter kind
/// and the commit authority differ: a control press in the app, or an intent that carries the
/// system's confirmation for a destructive change. Nothing here holds the store or decides a
/// grant; the host does, from the authority it is given (ADR-011, ADR-013).
public struct ActionAtlasActions: Sendable {
    public let backend: any ActionAtlasBackend
    public let entryPoint: AtlasEntryPoint

    public init(backend: any ActionAtlasBackend, entryPoint: AtlasEntryPoint) {
        self.backend = backend
        self.entryPoint = entryPoint
    }

    // MARK: Reads

    /// Collections ordered for choosing: the person's own first, then demo collections, each by
    /// title. Archived collections are left out unless asked for.
    public func collections(includeArchived: Bool = false) async throws(ActionAtlasError) -> [LabCollection] {
        let all = try await backend.collections(via: entryPoint)
        return all.filter { includeArchived || !$0.isArchived }.sorted(by: Self.choosingOrder)
    }

    /// The person's own collections that can take a new item.
    public func collectionsOfYourOwn() async throws(ActionAtlasError) -> [LabCollection] {
        try await collections().filter { $0.namespace == .user }
    }

    public func collection(_ id: CollectionID) async throws(ActionAtlasError) -> LabCollection {
        try await backend.collection(id, via: entryPoint)
    }

    public func item(_ id: ItemID) async throws(ActionAtlasError) -> LabItem {
        try await backend.item(id, via: entryPoint)
    }

    /// The items with these IDs that still exist, in the order asked. A missing ID is left out,
    /// which is how an entity query reports it.
    public func items(ids: [ItemID]) async throws(ActionAtlasError) -> [LabItem] {
        var found: [LabItem] = []
        for id in ids {
            do {
                found.append(try await item(id))
            } catch .missingItem {
                continue
            }
        }
        return found
    }

    /// The collections with these IDs that still exist, in the order asked.
    public func collections(ids: [CollectionID]) async throws(ActionAtlasError) -> [LabCollection] {
        var found: [LabCollection] = []
        for id in ids {
            do {
                found.append(try await collection(id))
            } catch .missingCollection {
                continue
            }
        }
        return found
    }

    /// Items matching `text` in titles and notes, ordered by title, using the domain's own
    /// matching rules. A missing collection is an error rather than an empty result.
    public func findItems(
        text: String? = nil,
        in collection: CollectionID? = nil,
        includeArchived: Bool = false,
        limit: Int = 50
    ) async throws(ActionAtlasError) -> [LabItem] {
        let filter: ItemFilter
        do {
            filter = try ItemFilter(collectionID: collection, text: text, includeArchived: includeArchived, limit: limit)
        } catch {
            throw .invalidInput(error)
        }
        return try await backend.items(filter, via: entryPoint)
    }

    /// Titles of the collections these items belong to, for display.
    public func collectionTitles(for items: [LabItem]) async throws(ActionAtlasError) -> [CollectionID: String] {
        var titles: [CollectionID: String] = [:]
        for id in Set(items.map(\.collectionID)) {
            do {
                titles[id] = try await collection(id).title.value
            } catch .missingCollection {
                continue
            }
        }
        return titles
    }

    // MARK: Changes

    /// Creates one of the person's own collections.
    public func createCollection(title: String, request: AtlasRequest) async throws(ActionAtlasError) -> AtlasOutcome<LabCollection> {
        let draft = CollectionDraft(id: request.newCollectionID, title: try Self.title(title))
        let receipt = try await commit(
            .createCollection(draft: draft), request: request, authority: routineAuthority,
            names: [.collection(draft.id): draft.title.value]
        )
        return AtlasOutcome(receipt: receipt, entity: try await collection(draft.id))
    }

    /// Creates an item in one of the person's own collections.
    ///
    /// With no collection named, the only collection of the person's own is used. When there are
    /// several, `choose` picks one (the system's disambiguation for an intent); without it the
    /// request is refused as ambiguous. With none, the person is told to create one first.
    public func createItem(
        title: String,
        note: String = "",
        in collectionID: CollectionID?,
        request: AtlasRequest,
        choose: AtlasChooser<LabCollection>? = nil
    ) async throws -> AtlasOutcome<LabItem> {
        let title = try Self.title(title)
        let note = try Self.note(note)
        let parent: LabCollection
        if let collectionID {
            parent = try await collection(collectionID)
        } else {
            let candidates = try await collectionsOfYourOwn()
            switch candidates.count {
            case 0:
                throw ActionAtlasError.noCollectionOfYourOwn
            case 1:
                parent = candidates[0]
            default:
                guard let choose else { throw ActionAtlasError.ambiguousCollection(candidates: candidates.count) }
                parent = try await choose(candidates)
            }
        }
        let draft = ItemDraft(id: request.newItemID, in: parent.id, title: title, note: note)
        let receipt = try await commit(
            .createItem(draft: draft), request: request, authority: routineAuthority,
            names: [.item(draft.id): title.value, .collection(parent.id): parent.title.value]
        )
        return AtlasOutcome(receipt: receipt, entity: try await item(draft.id))
    }

    /// Replaces an item's title, note, or both, at the revision the caller saw. A stale revision
    /// records a conflict receipt and throws `.conflict`; nothing is overwritten.
    public func updateItem(
        _ id: ItemID,
        expected: Revision,
        title: String?,
        note: String?,
        request: AtlasRequest
    ) async throws(ActionAtlasError) -> AtlasOutcome<LabItem> {
        let changes: ItemChanges
        do {
            changes = try ItemChanges(
                title: try title.map { raw throws(ValidationError) in try EntityTitle(raw) },
                note: try note.map { raw throws(ValidationError) in try ItemNote(raw) }
            )
        } catch {
            throw .invalidInput(error)
        }
        let current = try await item(id)
        let receipt = try await commit(
            .updateItem(id: id, expected: expected, changes: changes), request: request, authority: routineAuthority,
            names: [.item(id): (changes.title ?? current.title).value]
        )
        return AtlasOutcome(receipt: receipt, entity: try await item(id))
    }

    /// Archives an item at the revision the caller saw, after `confirm` returns.
    ///
    /// For an App Intent, `confirm` is the system's confirmation; only its return creates the
    /// `IntentConfirmation` that lets the host grant this one destructive commit. If it throws,
    /// the error propagates unchanged and nothing is committed or recorded. In the app, the
    /// control press is the approval and `confirm` does nothing.
    public func archiveItem(
        _ id: ItemID,
        expected: Revision,
        request: AtlasRequest,
        confirm: @Sendable (ArchivePrompt) async throws -> Void
    ) async throws -> AtlasOutcome<LabItem> {
        let current = try await item(id)
        let operation = DomainOperation.archiveItem(id: id, expected: expected)
        let prompt = ArchivePrompt(
            itemTitle: current.title.value,
            text: "Archive “\(current.title.value)”? It leaves normal view without being deleted, and its receipt in Native Lab offers an undo."
        )
        try await confirm(prompt)
        let authority: AtlasAuthority = switch entryPoint {
        case .appUI: .appControl
        case .appIntent: .intent(IntentConfirmation(confirmed: operation))
        }
        let receipt = try await commit(operation, request: request, authority: authority, names: [.item(id): current.title.value])
        return AtlasOutcome(receipt: receipt, entity: try await item(id))
    }

    /// Restores an archived item. Not destructive, so it needs no confirmation.
    public func restoreItem(_ id: ItemID, expected: Revision, request: AtlasRequest) async throws(ActionAtlasError) -> AtlasOutcome<LabItem> {
        let current = try await item(id)
        let receipt = try await commit(
            .restoreItem(id: id, expected: expected), request: request, authority: routineAuthority,
            names: [.item(id): current.title.value]
        )
        return AtlasOutcome(receipt: receipt, entity: try await item(id))
    }

    /// The portable form of one item in the chosen representation. Read-only: no receipt.
    public func exportItem(_ id: ItemID, as format: AtlasExportFormat) async throws(ActionAtlasError) -> AtlasExport {
        let item = try await item(id)
        let parent = try await collection(item.collectionID)
        return AtlasExport(document: PortableLabItem(item: item, collection: parent), format: format)
    }

    // MARK: Internals

    /// The authority for a non-destructive commit: a control press in the app, or an intent with
    /// no confirmation, which the host never turns into a grant.
    private var routineAuthority: AtlasAuthority {
        switch entryPoint {
        case .appUI: .appControl
        case .appIntent: .intent(nil)
        }
    }

    private func commit(
        _ operation: DomainOperation,
        request: AtlasRequest,
        authority: AtlasAuthority,
        names: [EntityReference: String]
    ) async throws(ActionAtlasError) -> ActionReceipt {
        // A cancelled task stops before the commit, never after it.
        guard !Task.isCancelled else { throw .cancelled }
        let receipt = try await backend.commit(operation, requestID: request.id, authority: authority, names: names)
        if let conflict = receipt.conflict { throw .conflict(conflict) }
        return receipt
    }

    private static func title(_ raw: String) throws(ActionAtlasError) -> EntityTitle {
        do { return try EntityTitle(raw) } catch { throw .invalidInput(error) }
    }

    private static func note(_ raw: String) throws(ActionAtlasError) -> ItemNote {
        do { return try ItemNote(raw) } catch { throw .invalidInput(error) }
    }

    private static func choosingOrder(_ lhs: LabCollection, _ rhs: LabCollection) -> Bool {
        if lhs.namespace != rhs.namespace { return lhs.namespace == .user }
        switch lhs.title.value.localizedStandardCompare(rhs.title.value) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
    }
}
