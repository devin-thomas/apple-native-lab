import DocumentsEverywhere
import SwiftUI

/// The content column for Documents Everywhere (LAB-009): sample list and adopt controls.
struct DocumentsEverywhereListColumn: View {
    @Bindable var window: MainWindowState
    @Environment(LabLibrary.self) private var library

    var body: some View {
        @Bindable var session = window.documentsEverywhere
        Group {
            switch session.phase {
            case .notStarted:
                ProgressView("Opening samples…")
                    .task { await session.open(library: library) }
            case .unavailable(let message):
                ContentUnavailableView(
                    "Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .ready:
                let rows = filtered(session.entries)
                List(selection: Binding(
                    get: { session.selectedID },
                    set: { new in
                        session.selectedID = new
                        if let new { session.select(new) }
                    }
                )) {
                    Section("Samples") {
                        ForEach(rows) { entry in
                            DocumentsEverywhereRow(entry: entry)
                                .tag(entry.id)
                        }
                    }
                    Section("Actions") {
                        DocumentsEverywhereControls(session: session)
                    }
                }
                .overlay {
                    if rows.isEmpty, !window.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        ContentUnavailableView.search(text: window.searchText)
                    }
                }
                .task { await session.refresh(library) }
            }
        }
        .navigationTitle("Documents Everywhere")
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
    }

    private func filtered(_ entries: [DocumentsEverywhereSession.Entry]) -> [DocumentsEverywhereSession.Entry] {
        let query = window.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.sample.displayName.localizedStandardContains(query)
                || $0.item.filename.localizedStandardContains(query)
        }
    }
}

struct DocumentsEverywhereDetailColumn: View {
    @Bindable var window: MainWindowState

    var body: some View {
        let session = window.documentsEverywhere
        DocumentsEverywherePreviewPane(
            preview: session.preview,
            providerMessage: session.providerStatusMessage,
            outcome: session.outcome
        )
        .navigationTitle(session.selected?.sample.displayName ?? "Preview")
    }
}
