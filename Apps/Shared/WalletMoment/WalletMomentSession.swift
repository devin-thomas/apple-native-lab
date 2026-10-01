import LabDomain
import Observation
import SwiftUI
import WalletMoment

/// LAB-038's shared names: the experiment's ID in the catalog and its title.
enum WalletMomentExperiment {
    static let id = WalletMoment.experimentID
    static let title = WalletMoment.title
    static let symbol = WalletMoment.symbol
}

/// One person's progress through Wallet Moment: unsigned preview, update inspection, operator
/// signing attempt, and saving the sample event card through the operation service.
@MainActor
@Observable
final class WalletMomentSession {
    private(set) var definition: PassDefinition = SampleEvent.definition
    /// The definition last saved successfully, used as the base for committed updates.
    private(set) var savedDefinition: PassDefinition?
    private(set) var clock: Date = SampleEvent.duringEvent
    private(set) var signingMessage: String?
    private(set) var signedNote: String?
    private(set) var message: String?
    private(set) var lastReceipt: ReceiptRecord?
    private(set) var savedItemID: ItemID?
    private(set) var savedCollectionID: CollectionID?
    private(set) var savedRevision: Revision?
    private(set) var isRunning = false

    /// Injected signing environment. Hosts use the unavailable default; an operator may replace it.
    @ObservationIgnored var signer: any PassSigningEnvironment = UnavailablePassSigner()

    @ObservationIgnored private var cardID = ItemID()
    @ObservationIgnored private let collectionID = CollectionID()
    @ObservationIgnored private let collectionRequest = RequestID()
    @ObservationIgnored private var saveRequest: RequestID?
    @ObservationIgnored private var updateRequest: RequestID?

    var preview: PassPreview { PassPreview(definition: definition, at: clock) }

    func showDuringEvent() {
        clock = SampleEvent.duringEvent
        message = nil
    }

    func showBeforeEvent() {
        clock = SampleEvent.beforeEvent
        message = nil
    }

    func showAfterExpiry() {
        clock = SampleEvent.afterExpiry
        message = nil
    }

    func resetPassState() {
        definition = SampleEvent.definition
        clock = SampleEvent.duringEvent
        signingMessage = nil
        signedNote = nil
        message = "Restored the sample event pass preview. Saved lab cards keep their receipts until archived."
    }

    /// Asks the signing environment for a test pass. Never embeds a key.
    func requestSignedPass() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            _ = try PassValidator.validate(definition)
            let artifact = try await signer.signedPass(for: definition)
            signedNote = artifact.note
            signingMessage = "Received \(artifact.bytes.count) bytes (\(artifact.provenance.rawValue))."
        } catch {
            signedNote = nil
            signingMessage = error.userMessage
        }
    }

    /// Saves the current preview as a local event card through the operation service.
    @discardableResult
    func saveEventCard(in library: LabLibrary) async -> ReceiptRecord? {
        guard library.phase == .ready, !isRunning, !library.isWorking, !Task.isCancelled else { return nil }
        isRunning = true
        defer { isRunning = false }
        if savedItemID != nil {
            message = "This event card is already saved. Apply an update or reset it first."
            return lastReceipt
        }
        let itemID = cardID
        let ops: (collection: DomainOperation, item: DomainOperation, itemID: ItemID)
        do {
            ops = try EventCardOperations.saveOperations(
                for: preview, collectionID: collectionID, itemID: itemID
            )
        } catch {
            message = error.userMessage
            return nil
        }
        let requestID = saveRequest ?? RequestID()
        saveRequest = requestID
        do {
            if savedCollectionID == nil {
                _ = try await library.submit(ops.collection, requestID: collectionRequest, authority: .userAction, names: [:])
                savedCollectionID = collectionID
            }
            guard !Task.isCancelled else {
                message = "Save cancelled. The empty event collection remains."
                return nil
            }
            let record = try await library.submit(ops.item, requestID: requestID, authority: .userAction, names: [:])
            saveRequest = nil
            if record.receipt.conflict == nil {
                savedItemID = itemID
                savedDefinition = definition
                savedRevision = record.receipt.changes.first(where: { $0.entity == .item(itemID) })?.newRevision ?? .initial
            }
            lastReceipt = record
            message = record.receipt.conflict == nil
                ? "Saved the local event card. Receipt recorded."
                : record.receipt.summary
            return record
        } catch {
            message = "The event card could not be saved. An event collection may remain; retry saving the card."
            return nil
        }
    }

    /// Resets only this session's saved fixture card, with the host's destructive grant path.
    func resetEventCard(in library: LabLibrary) async {
        guard !isRunning, !library.isWorking else { return }
        guard let itemID = savedItemID, let expected = savedRevision else {
            resetPassState()
            return
        }
        isRunning = true
        defer { isRunning = false }
        do {
            let record = try await library.submit(
                .archiveItem(id: itemID, expected: expected), requestID: RequestID(),
                authority: .userAction, names: [:]
            )
            lastReceipt = record
            guard record.receipt.conflict == nil else {
                message = record.receipt.summary
                return
            }
            savedItemID = nil
            savedRevision = nil
            savedDefinition = nil
            cardID = ItemID()
            saveRequest = nil
            updateRequest = nil
            resetPassState()
            message = "Archived this sample event card with a receipt. The preview is reset."
        } catch {
            message = "The card could not be reset. Its saved state is unchanged."
        }
    }

    /// Applies the seat update to the preview and, when a card was saved, commits the note change.
    @discardableResult
    func applySeatUpdate(in library: LabLibrary) async -> ReceiptRecord? {
        guard !isRunning, !library.isWorking, !Task.isCancelled else { return nil }
        let base = savedDefinition ?? (
            definition.updateTag == SampleEvent.definition.updateTag ? definition : SampleEvent.definition
        )
        let update: PassUpdate
        do {
            update = try PassValidator.validate(SampleEvent.seatUpdate, against: base)
        } catch {
            message = error.userMessage
            return nil
        }
        definition = base.applying(update)
        message = "Applied seat update \(update.updateTag) in the preview. Barcode is still display data only."

        guard let itemID = savedItemID, let expected = savedRevision else { return nil }
        guard library.phase == .ready, !isRunning, !library.isWorking else { return nil }
        isRunning = true
        defer { isRunning = false }
        let operation: DomainOperation
        do {
            operation = try EventCardOperations.updateOperation(
                itemID: itemID,
                expected: expected,
                current: base,
                update: update,
                at: clock
            )
        } catch {
            message = error.userMessage
            return nil
        }
        let requestID = updateRequest ?? RequestID()
        updateRequest = requestID
        do {
            let record = try await library.submit(operation, requestID: requestID, authority: .userAction, names: [:])
            updateRequest = nil
            if record.receipt.conflict == nil {
                savedDefinition = definition
                savedRevision = record.receipt.changes.first(where: { $0.entity == .item(itemID) })?.newRevision ?? expected.next()
            }
            lastReceipt = record
            message = record.receipt.conflict == nil
                ? "Updated the event card. The barcode still does not authorize changes."
                : record.receipt.summary
            return record
        } catch {
            message = "The update could not be saved. Nothing was changed."
            return nil
        }
    }
}
