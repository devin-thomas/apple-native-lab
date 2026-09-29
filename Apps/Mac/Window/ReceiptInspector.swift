import LabDomain
import SwiftUI

/// The receipt inspector column: one receipt in full, with the session's earlier receipts below
/// it to switch between.
struct ReceiptInspector: View {
    @Bindable var window: MainWindowState
    var focusedPane: FocusState<WindowPane?>.Binding
    @Environment(LabLibrary.self) private var library

    var body: some View {
        VStack(spacing: 0) {
            if let record = shown {
                ReceiptDetailView(record: record)
            } else {
                ContentUnavailableView(
                    "No Receipts Yet", systemImage: "list.bullet.rectangle",
                    description: Text("Every change made this session leaves a receipt here. Archive a sample or reset the demo to see one.")
                )
            }
            if library.receipts.count > 1 {
                Divider()
                earlier
            }
        }
        .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
        // One named group around the receipt and the list, rather than the name landing on
        // whichever child happens to be first.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Receipt inspector")
    }

    private var shown: ReceiptRecord? { window.shownReceipt(in: library) }

    private var earlier: some View {
        List(selection: $window.inspectedReceiptID) {
            Section("This session (\(library.receipts.count))") {
                ForEach(library.receipts) { record in
                    ReceiptRow(record: record)
                        .tag(record.id)
                }
            }
        }
        .frame(minHeight: 140, idealHeight: 200, maxHeight: 260)
        .focused(focusedPane, equals: .receipts)
        .accessibilityLabel("This session's receipts, \(library.receipts.count)")
    }
}
