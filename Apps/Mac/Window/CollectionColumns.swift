import LabDomain
import SwiftUI

/// The content column for the lab collection: every demo collection with its samples.
struct CollectionListColumn: View {
    @Bindable var window: MainWindowState
    @Environment(LabLibrary.self) private var library

    var body: some View {
        let contents = DemoSearch.filter(library.collections, text: window.searchText)
        List(selection: $window.itemID) {
            LibraryFailureBanner()
                .listRowSeparator(.hidden)
            ForEach(contents) { content in
                Section {
                    ForEach(content.items) { item in
                        DemoItemRow(item: item)
                            .tag(item.id)
                            .contextMenu { ArchiveToggleButton(item: item) }
                    }
                } header: {
                    CollectionHeader(collection: content.collection, itemCount: content.items.count)
                }
            }
        }
        .overlay {
            if library.collections.isEmpty {
                LibraryPhaseView()
            } else if contents.isEmpty {
                ContentUnavailableView.search(text: window.searchText)
            }
        }
        .navigationTitle("Lab Collection")
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        .toolbar {
            ToolbarItem {
                ResetDemoButton(isConfirming: $window.isConfirmingReset)
                    .help("Restore every demo sample (⇧⌘R)")
            }
        }
    }
}

private struct CollectionHeader: View {
    let collection: LabCollection
    let itemCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(collection.title.value)
            Text("Demo")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(Capsule().strokeBorder(.secondary))
            Spacer()
            Text(itemCount == 1 ? "1 item" : "\(itemCount) items")
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(collection.title.value), demo collection, \(itemCount) items")
        .accessibilityAddTraits(.isHeader)
    }
}

/// The detail column for the lab collection: the selected sample, or the namespaces.
struct CollectionDetailColumn: View {
    let itemID: ItemID?

    var body: some View {
        if let itemID {
            DemoItemDetailView(itemID: itemID)
        } else {
            Form {
                Section {
                    NamespaceSummary()
                } header: {
                    Text("Data on this Mac")
                } footer: {
                    Text("Both namespaces live in one file in this app's container: \(LabStoreLocation.displayPath). Select a sample to see its record.")
                }
            }
            .formStyle(.grouped)
        }
    }
}
