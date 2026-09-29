import LabDomain
import SwiftUI

/// The main window's keyboard stops in reading order: the sidebar, its search field, the results,
/// then the receipt inspector's list of this session's receipts when it is showing.
///
/// Left to itself, the window's key-view loop runs sidebar, search, receipts, results, and once an
/// experiment is selected Tab can stay on the receipts list. The window routes forward Tab through
/// this order instead. Shift-Tab stays with the system, which still reaches every stop and, with
/// keyboard navigation on, every control in the detail column and the inspector.
enum WindowPane: Hashable, CaseIterable {
    case sidebar
    case search
    case results
    case receipts

    /// Where Tab goes from this stop. The receipts list is skipped when it is not showing.
    func next(receiptsShowing: Bool) -> WindowPane {
        switch self {
        case .sidebar: .search
        case .search: .results
        case .results: receiptsShowing ? .receipts : .sidebar
        case .receipts: .sidebar
        }
    }
}

extension MainWindowState {
    /// The receipt the inspector shows: the one picked, or the newest.
    func shownReceipt(in library: LabLibrary) -> ReceiptRecord? {
        inspectedReceiptID.flatMap(library.receipt(id:)) ?? library.latestReceipt
    }

    /// The sample selected in the lab collection, if the collection is showing.
    func selectedSample(in library: LabLibrary) -> LabItem? {
        guard destination == .collection else { return nil }
        return itemID.flatMap(library.item(id:))
    }

    /// Whether the inspector's list of this session's receipts is on screen.
    func showsReceiptList(in library: LabLibrary) -> Bool {
        showsInspector && library.receipts.count > 1
    }
}
