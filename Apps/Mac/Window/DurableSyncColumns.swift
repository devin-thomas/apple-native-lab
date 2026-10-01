import DurableSyncLedger
import SwiftUI

/// The content column for the durable sync ledger (LAB-017): the two fixture devices.
struct DurableSyncListColumn: View {
    @Bindable var window: MainWindowState

    var body: some View {
        @Bindable var session = window.durableSync
        List(selection: $session.selected) {
            Section {
                ForEach(session.panes) { pane in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pane.label)
                        Text(paneSummary(pane.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(pane.id)
                    .accessibilityLabel("\(pane.label), \(paneSummary(pane.state))")
                }
            } footer: {
                Text("Fixture replay on this Mac. Not iCloud.")
            }
        }
        .navigationTitle(DurableSyncExperiment.title)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        .task { await session.openIfNeeded() }
    }

    private func paneSummary(_ state: RecordState) -> String {
        switch state {
        case .absent: "No edit yet"
        case .live(let title, _): title
        case .deleted: "Deleted"
        case .conflict: "Edits made apart"
        }
    }
}

/// The detail column: the selected device's record, the conflict choice, and the document exchange.
struct DurableSyncDetailColumn: View {
    @Bindable var window: MainWindowState

    var body: some View {
        DurableSyncEditor(session: window.durableSync, showsDevicePicker: false)
    }
}
