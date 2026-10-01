import Foundation
import LabDomain

/// Saves a sample event card into the lab as a user item, and applies updates to it, always
/// through `WalletMomentBackend` so each change has a receipt.
///
/// The barcode on the card is stored as display metadata in `ItemExtras` at creation. Reading it
/// back never issues a grant: authorization comes only from the actor scope the host already holds.
/// Item extras are write-once (DATA_CONTRACTS), so later updates change the title and note only.
public enum EventCardOperations {
    /// Stable title for the collection that holds experiment-owned event cards.
    public static let collectionTitle = "Event passes"

    /// Builds the `createCollection` + `createItem` operations for a validated preview. The caller
    /// commits them in order through the backend. Cancellation between the two leaves only the
    /// collection.
    public static func saveOperations(
        for preview: PassPreview,
        collectionID: CollectionID = CollectionID(),
        itemID: ItemID = ItemID()
    ) throws(WalletMomentError) -> (collection: DomainOperation, item: DomainOperation, itemID: ItemID) {
        let definition = try PassValidator.validate(preview.definition)
        let collectionTitle: EntityTitle
        let title: EntityTitle
        let note: ItemNote
        let extras: ItemExtras
        do {
            collectionTitle = try EntityTitle(Self.collectionTitle)
            title = try EntityTitle(definition.eventName)
            note = try ItemNote(noteText(for: definition, lifecycle: preview.lifecycle))
            extras = try extrasJSON(for: definition)
        } catch let error as WalletMomentError {
            throw error
        } catch is ValidationError {
            throw .stateChanged
        } catch is ExtrasRejection {
            throw .stateChanged
        } catch {
            throw .stateChanged
        }
        let collection = DomainOperation.createCollection(
            draft: CollectionDraft(id: collectionID, title: collectionTitle)
        )
        let item = DomainOperation.createItem(
            draft: ItemDraft(id: itemID, in: collectionID, title: title, note: note, extras: extras)
        )
        return (collection, item, itemID)
    }

    /// An `updateItem` that applies a validated pass update to a saved card's title and note.
    public static func updateOperation(
        itemID: ItemID,
        expected: Revision,
        current: PassDefinition,
        update: PassUpdate,
        at now: Date = Date()
    ) throws(WalletMomentError) -> DomainOperation {
        let validated = try PassValidator.validate(update, against: current)
        let next = current.applying(validated)
        _ = try PassValidator.validate(next)
        let lifecycle = PassLifecycle.state(of: next, at: now)
        let title: EntityTitle
        let note: ItemNote
        do {
            title = try EntityTitle(next.eventName)
            note = try ItemNote(noteText(for: next, lifecycle: lifecycle))
        } catch {
            throw .stateChanged
        }
        let changes: ItemChanges
        do {
            changes = try ItemChanges(title: title, note: note)
        } catch {
            throw .nothingToUpdate
        }
        return .updateItem(id: itemID, expected: expected, changes: changes)
    }

    /// Archives experiment-owned event cards. Each archive is its own receipt.
    public static func resetOperations(items: [LabItem]) -> [DomainOperation] {
        items.filter(isExperimentOwned).filter { !$0.isArchived }.map {
            .archiveItem(id: $0.id, expected: $0.revision)
        }
    }

    public static func isExperimentOwned(_ item: LabItem) -> Bool {
        guard !item.extras.isEmpty else { return false }
        guard let data = item.extras.json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object[WalletMoment.extrasExperimentKey] as? String == WalletMoment.experimentID
            && object[WalletMoment.extrasKindKey] as? String == WalletMoment.extrasKindValue
    }

    /// Runs operations one at a time and stops cleanly when cancelled.
    public static func perform(
        _ operations: [DomainOperation],
        isolation: isolated (any Actor)? = #isolation,
        commit: (DomainOperation) async throws -> ActionReceipt
    ) async throws -> (receipts: [ActionReceipt], wasCancelled: Bool) {
        var receipts: [ActionReceipt] = []
        for operation in operations {
            if Task.isCancelled { return (receipts, true) }
            receipts.append(try await commit(operation))
        }
        return (receipts, false)
    }

    public static func noteText(for definition: PassDefinition, lifecycle: PassLifecycleState) -> String {
        """
        \(definition.organizationName)
        \(definition.venue) · Seat \(definition.seat)
        Serial \(definition.serialNumber)
        \(lifecycle.title): \(lifecycle.sentence)
        Barcode (\(definition.barcode.format.rawValue)): \(definition.barcode.altText)
        Update tag: \(definition.updateTag)
        Unsigned local event card. The barcode is display data only and does not authorize changes.
        """
    }

    public static func extrasJSON(for definition: PassDefinition) throws -> ItemExtras {
        let object: [String: String] = [
            WalletMoment.extrasExperimentKey: WalletMoment.experimentID,
            WalletMoment.extrasKindKey: WalletMoment.extrasKindValue,
            "passID": definition.id.uuidString,
            "serialNumber": definition.serialNumber,
            "updateTag": definition.updateTag,
            "expiresAt": ISO8601DateFormatter().string(from: definition.expiresAt),
            "barcodeFormat": definition.barcode.format.rawValue,
            "barcodeMessage": definition.barcode.message,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw WalletMomentError.stateChanged
        }
        return try ItemExtras(json: json)
    }
}
