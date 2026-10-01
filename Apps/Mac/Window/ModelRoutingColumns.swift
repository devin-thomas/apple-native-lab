import ModelRouting
import SwiftUI

/// Mac content column for Model Routing Observatory.
struct ModelRoutingListColumn: View {
    @Bindable var window: MainWindowState

    var body: some View {
        List(selection: $window.modelRoutingPane) {
            Section {
                Text("Observatory")
                    .font(.title2.weight(.semibold))
            }
            Section("Panes") {
                Label("Route board", systemImage: ModelRoutingExperiment.symbol)
                    .tag(ModelRoutingPane.board)
                Label("Usage receipts", systemImage: "list.clipboard")
                    .tag(ModelRoutingPane.receipts)
            }
        }
        .navigationTitle(ModelRoutingExperiment.title)
    }
}

enum ModelRoutingPane: String, Hashable {
    case board
    case receipts
}

/// Mac detail column.
struct ModelRoutingDetailColumn: View {
    @Bindable var window: MainWindowState
    @Environment(LabLibrary.self) private var library
    @State private var session = ModelRoutingSession()

    var body: some View {
        Group {
            switch window.modelRoutingPane {
            case .board, .none:
                ModelRoutingPageContent(session: session)
                    .overlay {
                        if library.collections.isEmpty { LibraryPhaseView() }
                    }
            case .receipts:
                ModelRoutingReceiptsPane(session: session)
            }
        }
        .task { await session.start(with: library) }
    }
}

private struct ModelRoutingReceiptsPane: View {
    @Bindable var session: ModelRoutingSession

    var body: some View {
        List {
            if session.usage.isEmpty {
                ContentUnavailableView(
                    "No Usage Yet",
                    systemImage: "list.clipboard",
                    description: Text("Run local generation, the manual workflow, or a cloud attempt to record usage without raw prompts.")
                )
            } else {
                ForEach(session.usage) { receipt in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(receipt.route.title) {
                            Text(receipt.outcome.rawValue)
                        }
                        Text(receipt.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Usage receipts")
    }
}
