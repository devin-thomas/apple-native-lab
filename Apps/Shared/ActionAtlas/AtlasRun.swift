import ActionAtlas
import LabDomain
import Observation
import SwiftUI

/// One form's progress: whether it is running, what went wrong, and the receipt it left.
///
/// The form's request stays the same until its inputs change or a change commits, so pressing
/// the button again after a failure retries the same request and commits at most once.
@MainActor
@Observable
final class AtlasRun {
    private(set) var isRunning = false
    /// Why the last run failed, as a sentence for the person.
    private(set) var message: String?
    /// The receipt of the last run's change, including a conflict that changed nothing.
    private(set) var record: ReceiptRecord?
    private(set) var request = AtlasRequest()

    /// New inputs are a new decision, so they get a new request ID.
    func inputsChanged() {
        request = AtlasRequest()
    }

    /// Runs one action with this form's request. `body` returns the change's receipt, or `nil`
    /// for a read. Returns whether it succeeded.
    @discardableResult
    func perform(in library: LabLibrary, _ body: (AtlasRequest) async throws -> ActionReceipt?) async -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        defer { isRunning = false }
        message = nil
        let current = request
        do {
            let receipt = try await body(current)
            record = receipt.flatMap { library.receipt(id: $0.operationID) }
            if receipt != nil { request = AtlasRequest() }
            return true
        } catch {
            message = (error as? ActionAtlasError)?.message ?? "Something unexpected went wrong. Nothing was changed."
            // A conflict still records a receipt under this request; show it, and decide anew next time.
            record = library.receipts.first { $0.receipt.requestID == current.id }
            if record != nil { request = AtlasRequest() }
            return false
        }
    }
}

/// An item as a picker offers it: title, collection, and whether it is archived.
struct AtlasItemChoice: Identifiable, Hashable {
    let item: LabItem
    let collectionTitle: String

    var id: ItemID { item.id }

    var label: String {
        [item.title.value, detail].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Collection, then "Archived" and "Demo sample" when they apply.
    var detail: String {
        [collectionTitle.isEmpty ? nil : collectionTitle, item.isArchived ? "Archived" : nil,
         item.namespace == .demo ? "Demo sample" : nil]
            .compactMap(\.self).joined(separator: " · ")
    }
}

/// What the forms choose from: every item and collection, read through the service as the app UI.
@MainActor
@Observable
final class AtlasChoices {
    private(set) var items: [AtlasItemChoice] = []
    private(set) var collections: [LabCollection] = []
    private(set) var loadMessage: String?

    var ownCollections: [LabCollection] { collections.filter { $0.namespace == .user } }

    func load(_ actions: ActionAtlasActions) async {
        do {
            let found = try await actions.findItems(includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
            let titles = try await actions.collectionTitles(for: found)
            items = found.map { AtlasItemChoice(item: $0, collectionTitle: titles[$0.collectionID] ?? "") }
            collections = try await actions.collections()
            loadMessage = nil
        } catch {
            loadMessage = error.message
        }
    }

    func item(_ id: ItemID?) -> AtlasItemChoice? {
        id.flatMap { id in items.first { $0.id == id } }
    }
}

extension LabLibrary {
    /// The actions the in-app browser runs: the app-UI entry point over this library.
    var atlasActions: ActionAtlasActions {
        ActionAtlasActions(backend: LibraryAtlasBackend(library: self), entryPoint: .appUI)
    }
}
