import LabDomain
import SwiftUI

/// The lab's own data on iPhone: the latest receipt first, then every demo collection with its
/// samples, then the namespaces. Reset Demo stays in the navigation bar, so it is reachable at
/// every text size without scrolling.
struct CollectionTab: View {
    private enum Route: Hashable {
        case item(ItemID)
        case receipt(OperationID)
        case receipts
    }

    @Environment(LabLibrary.self) private var library
    @State private var path = NavigationPath()
    @State private var isConfirmingReset = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                LibraryFailureBanner()
                    .listRowSeparator(.hidden)
                if let latest = library.latestReceipt {
                    Section("Latest receipt") {
                        NavigationLink(value: Route.receipt(latest.id)) {
                            ReceiptRow(record: latest)
                        }
                    }
                }
                ForEach(library.collections) { content in
                    Section {
                        ForEach(content.items) { item in
                            NavigationLink(value: Route.item(item.id)) {
                                DemoItemRow(item: item)
                            }
                            .swipeActions(edge: .trailing) {
                                ArchiveToggleButton(item: item)
                                    .tint(item.isArchived ? .blue : .orange)
                            }
                            .contextMenu { ArchiveToggleButton(item: item) }
                        }
                    } header: {
                        Text("\(content.collection.title.value) · Demo")
                    }
                }
                if library.census != nil {
                    Section {
                        NamespaceSummary()
                    } header: {
                        Text("Data on this iPhone")
                    } footer: {
                        Text("Both namespaces live in one file in this app's container: \(LabStoreLocation.displayPath).")
                    }
                }
            }
            .overlay {
                if library.collections.isEmpty { LibraryPhaseView() }
            }
            .navigationTitle("Collection")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .item(let id):
                    DemoItemDetailView(itemID: id)
                        .navigationBarTitleDisplayMode(.inline)
                case .receipt(let id):
                    receiptDetail(id)
                case .receipts:
                    ReceiptListContent()
                        .navigationTitle("Receipts")
                }
            }
            // The receipts list links by operation ID.
            .navigationDestination(for: OperationID.self) { id in
                receiptDetail(id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: Route.receipts) {
                        Label("Receipts", systemImage: "list.bullet.rectangle")
                    }
                    .accessibilityHint("Every receipt from this session")
                }
                ToolbarItem(placement: .primaryAction) {
                    ResetDemoButton(isConfirming: $isConfirmingReset)
                }
            }
            .resetDemoConfirmation(isPresented: $isConfirmingReset) { record in
                // Show the new receipt right away.
                var receiptPath = NavigationPath()
                receiptPath.append(Route.receipt(record.id))
                path = receiptPath
            }
        }
    }

    @ViewBuilder private func receiptDetail(_ id: OperationID) -> some View {
        if let record = library.receipt(id: id) {
            ReceiptDetailView(record: record)
                .navigationTitle("Receipt")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
