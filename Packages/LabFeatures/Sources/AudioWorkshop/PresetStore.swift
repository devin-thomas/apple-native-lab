import Foundation
import LabDomain

/// What the preset store needs from the host: reads and commits through the host's own
/// `OperationService`, under the app-UI actor. Nothing here holds the store.
public protocol PresetBackend: Sendable {
    /// The preset collection, or `nil` when it has never been created.
    func collection(_ id: CollectionID) async throws(PresetStoreError) -> LabCollection?
    /// The items in a collection, archived ones included.
    func items(in collection: CollectionID) async throws(PresetStoreError) -> [LabItem]
    /// Commits one request and returns its receipt. `names` titles entities for the receipt list.
    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(PresetStoreError) -> ActionReceipt
}

/// Why a preset was not saved or listed. Each case changed nothing.
public enum PresetStoreError: Error, Hashable, Sendable {
    case unavailable(reason: String)
    case refused(OperationError)
    case invalidName(ValidationError)
    case cancelled

    public var message: String {
        switch self {
        case .unavailable(let reason): reason
        case .refused(.ruleViolation(.collectionArchived)):
            "The \(AudioWorkshop.presetCollectionTitle) collection is archived. Restore it in the Lab Collection to save presets. Nothing was saved."
        case .refused(.unauthorized): "This entry point may not save presets. Nothing was saved."
        case .refused(.storeFailure): "Native Lab could not save its data. Nothing was saved. Try again."
        case .refused: "The preset could not be saved. Nothing was saved."
        case .invalidName(.emptyTitle): "Give the preset a name."
        case .invalidName(.titleTooLong(let limit)): "A preset name is at most \(limit) characters."
        case .invalidName: "A preset name cannot contain control characters."
        case .cancelled: "Cancelled. Nothing was saved."
        }
    }
}

/// One decision to save a preset. Create it once when the person presses Save and reuse it on a
/// retry: its request ID and item ID stay the same, so a retry returns the original receipt
/// instead of saving a second copy.
public struct PresetSaveRequest: Hashable, Sendable {
    public let requestID: RequestID
    public let itemID: ItemID
    public let title: EntityTitle
    public let preset: AudioGraphPreset

    public init(named name: String, preset: AudioGraphPreset) throws(PresetStoreError) {
        do { title = try EntityTitle(name) } catch { throw .invalidName(error) }
        self.preset = preset
        requestID = RequestID()
        itemID = ItemID()
    }

    var operation: DomainOperation {
        // The note is the readable summary, which search finds; the extras are what loads.
        let note = (try? ItemNote(preset.summary)) ?? .empty
        return .createItem(draft: ItemDraft(
            id: itemID, in: AudioWorkshop.presetCollectionID, title: title, note: note, extras: preset.extras
        ))
    }
}

/// A preset item as the workshop reads it. An item it cannot read is listed with the reason,
/// never loaded.
public struct SavedPreset: Identifiable, Hashable, Sendable {
    public let id: ItemID
    public let title: String
    public let revision: Revision
    public let isArchived: Bool
    public let content: Result<AudioGraphPreset, PresetRejection>

    init(_ item: LabItem) {
        id = item.id
        title = item.title.value
        revision = item.revision
        isArchived = item.isArchived
        do { content = .success(try AudioGraphPreset(extras: item.extras)) } catch { content = .failure(error) }
    }

    public var preset: AudioGraphPreset? { try? content.get() }
}

/// Saving and listing presets. A save is an ordinary item creation in the person's preset
/// collection, so it is authorized, idempotent per request, and recorded with a receipt whose
/// undo archives the preset (ADR-011). Presets are the person's data: Reset Demo never touches them.
public struct PresetStore: Sendable {
    public let backend: any PresetBackend

    public init(backend: any PresetBackend) {
        self.backend = backend
    }

    /// Saves one preset, creating the preset collection first if it does not exist yet.
    public func save(_ request: PresetSaveRequest) async throws(PresetStoreError) -> ActionReceipt {
        if try await backend.collection(AudioWorkshop.presetCollectionID) == nil {
            guard !Task.isCancelled else { throw .cancelled }
            let create = DomainOperation.createCollection(draft: CollectionDraft(
                id: AudioWorkshop.presetCollectionID, title: try! EntityTitle(AudioWorkshop.presetCollectionTitle)
            ))
            do {
                _ = try await backend.commit(create, requestID: RequestID(), names: [:])
            } catch .refused(.ruleViolation(.alreadyExists)) {
                // Another save created it first; the collection is what matters.
            }
        }
        // The last point at which cancelling leaves nothing behind; after it the commit runs whole.
        guard !Task.isCancelled else { throw .cancelled }
        return try await backend.commit(
            request.operation, requestID: request.requestID,
            names: [.item(request.itemID): request.title.value]
        )
    }

    /// Every preset item in the order the domain sorts items (by title), archived ones excluded.
    public func presets() async throws(PresetStoreError) -> [SavedPreset] {
        guard try await backend.collection(AudioWorkshop.presetCollectionID) != nil else { return [] }
        return try await backend.items(in: AudioWorkshop.presetCollectionID)
            .filter { !$0.isArchived }
            .map(SavedPreset.init)
    }
}
