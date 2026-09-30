import LabDomain
import PortableObjects
import SwiftUI

/// The content column for Portable Objects (LAB-008): import controls, then every object by
/// collection. Each row drags as the complete document; the whole list takes drops.
struct PortableObjectsListColumn: View {
    @Bindable var window: MainWindowState
    @Environment(LabLibrary.self) private var library

    var body: some View {
        @Bindable var session = window.portableObjects
        let groups = filtered(session.groups)
        List(selection: $session.selectedItemID) {
            Section {
                PortableImportControls(session: session)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        PortableObjectRow(entry: entry, object: session.portableObject(for: entry))
                            .tag(entry.id)
                    }
                } header: {
                    Text(group.collection.namespace == .demo ? "\(group.collection.title.value) · Demo" : group.collection.title.value)
                }
            }
        }
        .overlay {
            if groups.isEmpty, !window.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search(text: window.searchText)
            }
        }
        .dropDestination(for: IncomingObject.self) { items, _ in
            Task { await session.receive(items, library: library) }
        }
        .navigationTitle("Portable Objects")
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        .task { await session.load(library) }
        .onChange(of: library.latestReceipt?.id) { Task { await session.load(library) } }
        .onChange(of: session.selectedItemID) { _, selected in
            // Choosing another object leaves a finished import's summary behind.
            if session.review == nil, session.outcome?.itemID != selected { session.dismissOutcome() }
        }
    }

    private func filtered(_ groups: [PortableObjectsSession.Group]) -> [PortableObjectsSession.Group] {
        let needle = window.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group in
            let entries = group.entries.filter {
                $0.item.title.value.localizedStandardContains(needle) || $0.item.note.value.localizedStandardContains(needle)
            }
            return entries.isEmpty ? nil : PortableObjectsSession.Group(collection: group.collection, entries: entries)
        }
    }
}

/// The detail column: the import under review, else the selected object's export preview. Each
/// receipt opens in the window's receipt inspector.
struct PortableObjectsDetailColumn: View {
    @Bindable var window: MainWindowState

    var body: some View {
        let session = window.portableObjects
        if let review = session.review {
            ImportReviewView(session: session, review: review) { record in
                window.inspect(record)
            }
            .id(review.id)
        } else {
            VStack(spacing: 0) {
                if let outcome = session.outcome {
                    PortableOutcomeView(outcome: outcome) { record in window.inspect(record) }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }
                if let preview = session.exportPreview(for: session.selectedItemID) {
                    ExportPreviewView(preview: preview)
                        .id(preview.document.itemID)
                } else {
                    ContentUnavailableView(
                        "Select an Object", systemImage: "shippingbox",
                        description: Text("See what an export holds, then drag it, export it, or share it. Drop an object from another window or an .anlab file on the list to import it.")
                    )
                }
            }
        }
    }
}
