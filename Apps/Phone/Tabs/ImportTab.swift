import LabCatalog
import LabDomain
import ShareIngress
import SwiftUI

/// The share inbox (LAB-007 Share Ingress Station). Paste and Choose Files stage into the inbox in
/// every build; a SystemSurfaces build also lists what the share extension staged. Each waiting
/// import opens its review screen, where the person chooses a collection and Add.
struct ImportTab: View {
    let model: LabModel
    @State private var inbox = ShareInboxModel.shared
    @State private var isChoosingFiles = false
    @State private var path = NavigationPath()
    @Environment(LabLibrary.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    InboxIntakeControls(model: inbox, isChoosingFiles: $isChoosingFiles)
                    InboxIntakeStatus(model: inbox)
                } header: {
                    Text("Add to the inbox")
                } footer: {
                    InboxLimitsText(limits: inbox.limits)
                }
                waitingSection
                if !inbox.snapshot.quarantined.isEmpty {
                    Section("Set aside") {
                        ForEach(inbox.snapshot.quarantined) { entry in
                            QuarantineRow(entry: entry, model: inbox)
                        }
                    }
                }
                Section {
                    ShareSheetStatusText(status: inbox.shareSheet)
                        .fixedSize(horizontal: false, vertical: true)
                    if let experiment = model.registry?.experiment(id: "LAB-007") {
                        NavigationLink(value: experiment.id) {
                            Text("\(experiment.title) (\(experiment.id))")
                        }
                    }
                } header: {
                    Text("Sharing from other apps")
                } footer: {
                    Text("Anything you add goes into your own data, which Reset Demo never changes.")
                }
            }
            .navigationTitle("Import")
            .refreshable { await inbox.refresh() }
            .fileImporter(isPresented: $isChoosingFiles, allowedContentTypes: ShareInboxTypes.choosable, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result, !urls.isEmpty { inbox.importFiles(urls) }
            }
            .navigationDestination(for: InboxEntry.ID.self) { id in
                if let entry = inbox.snapshot.entry(id) ?? inbox.added[id]?.entry {
                    InboxEntryDetail(entry: entry, model: inbox) { record in path.append(record.id) }
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    ContentUnavailableView("No Longer Waiting", systemImage: "tray",
                                           description: Text("This import was added or removed."))
                }
            }
            .navigationDestination(for: OperationID.self) { id in
                if let record = library.receipt(id: id) {
                    ReceiptDetailView(record: record)
                        .navigationTitle("Receipt")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .navigationDestination(for: RegisteredExperiment.ID.self) { id in
                if let experiment = model.registry?.experiment(id: id) {
                    ExperimentDetailView(experiment: experiment)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .task {
            await inbox.start()
            await inbox.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // The share extension may have staged something while the app was in the background.
            if phase == .active { Task { await inbox.refresh() } }
        }
        .onChange(of: path.count) { old, new in
            if new < old { Task { await inbox.refresh() } }
        }
    }

    @ViewBuilder private var waitingSection: some View {
        Section {
            if inbox.snapshot.entries.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(inbox.snapshot.entries) { entry in
                NavigationLink(value: entry.id) {
                    InboxEntryRow(entry: entry)
                }
            }
        } header: {
            Text("Waiting for review")
        }
    }

    private var emptyText: String {
        switch inbox.phase {
        case .unavailable(let reason): reason
        case .notStarted, .opening: "Opening the inbox…"
        case .ready: "Nothing is waiting. Paste or choose files above."
        }
    }
}
