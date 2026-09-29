import LabCatalog
import LabDomain
import LabSupport
import Observation
import SwiftUI

/// What the sidebar selects: the lab's own data, or a slice of the experiment catalog.
enum SidebarDestination: Hashable {
    case collection
    case catalog(CatalogScope)

    var title: String {
        switch self {
        case .collection: "Lab Collection"
        case .catalog(let scope): scope.title
        }
    }

    /// A short string for scene storage. It holds no content, only which list was showing.
    var storageKey: String {
        switch self {
        case .collection: "collection"
        case .catalog(.all): "all"
        case .catalog(.milestone(let milestone)): "milestone:\(milestone.rawValue)"
        case .catalog(.category(let category)): "category:\(category)"
        case .catalog(.state(let state)): "state:\(state.rawValue)"
        }
    }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count == 2 ? parts[1] : nil) {
        case ("collection", nil): self = .collection
        case ("all", nil): self = .catalog(.all)
        case ("milestone", let raw?): guard let milestone = Milestone(rawValue: raw) else { return nil }
            self = .catalog(.milestone(milestone))
        case ("category", let name?): self = .catalog(.category(name))
        case ("state", let raw?): guard let state = ImplementationState(rawValue: raw) else { return nil }
            self = .catalog(.state(state))
        default: return nil
        }
    }
}

/// One main window's navigation and presentation state. Menu commands reach the frontmost window's
/// state through `FocusedValues.mainWindow`.
@MainActor
@Observable
final class MainWindowState {
    var destination: SidebarDestination? = .catalog(.milestone(.m1))
    var experimentID: RegisteredExperiment.ID?
    var itemID: ItemID?
    var searchText = ""
    /// Incremented to ask the window to focus its search field.
    var searchRequests = 0
    var showsInspector = false
    /// The receipt the inspector shows; `nil` means the newest one.
    var inspectedReceiptID: OperationID?
    var isConfirmingReset = false

    func focusSearch() { searchRequests += 1 }

    func showCollection() { destination = .collection }

    /// Opens the inspector on a receipt that just arrived.
    func inspect(_ record: ReceiptRecord) {
        inspectedReceiptID = record.id
        showsInspector = true
    }
}

extension FocusedValues {
    @Entry var mainWindow: MainWindowState?
}
