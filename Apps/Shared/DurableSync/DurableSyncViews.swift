import DurableSyncLedger
import LabCatalog
import SwiftUI
import UniformTypeIdentifiers

/// The ledger on one screen (LAB-017). iPhone and iPad push it from the catalog page. The Mac
/// shows the devices in the content column and this editor in the detail column.
struct DurableSyncPage: View {
    @State private var session = DurableSyncSession()

    var body: some View {
        DurableSyncEditor(session: session, showsDevicePicker: true)
            .navigationTitle(DurableSyncExperiment.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await session.openIfNeeded() }
    }
}

/// One device's record, the choice when two edits were made apart, and the manual document.
struct DurableSyncEditor: View {
    @Bindable var session: DurableSyncSession
    var showsDevicePicker: Bool
    @State private var title = "Field note"
    @State private var note = "North count"
    @State private var confirmingDelete = false
    @State private var confirmingReset = false
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportFile: LedgerExchangeFile?

    var body: some View {
        Form {
            Section {
                Text(DurableSyncExperiment.replayCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsDevicePicker {
                Section {
                    Picker("Device", selection: $session.selected) {
                        ForEach(session.panes) { pane in
                            Text(pane.label).tag(pane.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            if let pane = session.selectedPane {
                Section {
                    LabeledContent("Record", value: recordSummary(pane.state))
                    Text(pane.explanation)
                        .fixedSize(horizontal: false, vertical: true)
                    if let receipt = pane.receipt {
                        LabeledContent("Receipt", value: receipt)
                    }
                } header: {
                    Text(pane.label)
                }
                conflictSection(pane.state)
            }
            Section {
                TextField("Title", text: $title)
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(2 ... 4)
            } header: {
                Text("Edit")
            } footer: {
                Text("Saving writes the edit to this device first. Reconnect exchanges it. Nothing is uploaded.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Button("Save Edit") {
                    let title = title
                    let note = note
                    Task { await session.save(title: title, note: note) }
                }
                .disabled(session.isWorking)
                .accessibilityHint("Writes this title and note on the selected device.")
                Button("Delete Record", role: .destructive) { confirmingDelete = true }
                    .disabled(session.isWorking)
                    .accessibilityHint("Records a deletion. A reinstall does not bring the record back.")
                Button("Reconnect") { Task { await session.reconnect() } }
                    .disabled(session.isWorking)
                    .accessibilityHint("Exchanges edits through the local profile, or says why it cannot.")
            }
            Section {
                Toggle("Sync profile", isOn: Binding(
                    get: { session.cloudEnabled },
                    set: { enabled in Task { await session.setCloudEnabled(enabled) } }
                ))
                .disabled(session.isWorking)
                .accessibilityHint("Turns the local profile off. Export and import still work.")
            } footer: {
                Text("The profile is a private folder on this device. Turning it off leaves the ledger and the document exchange.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Button("Export Document") { Task { await beginExport() } }
                    .disabled(session.isWorking)
                    .accessibilityHint("Saves this device's ledger as a JSON file you choose.")
                Button("Import Document") { isImporting = true }
                    .disabled(session.isWorking)
                    .accessibilityHint("Merges a ledger file into the selected device.")
            } header: {
                Text("Manual exchange")
            } footer: {
                Text("Use a file when the profile is off. A document from another account is refused.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = session.message {
                Section {
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Result")
                }
            }
            Section {
                Button("Reset Demo", role: .destructive) { confirmingReset = true }
                    .disabled(session.isWorking)
                    .accessibilityHint("Removes only this experiment's ledger folder.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete this record?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await session.deleteSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This records a tombstone on the selected device. Reinstalling does not bring the record back.")
        }
        .confirmationDialog("Reset the ledger demo?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset Demo", role: .destructive) { Task { await session.reset() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the ledger folder for this experiment. The lab collection stays.")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportFile,
            contentType: .json,
            defaultFilename: "ledger"
        ) { result in
            if case .failure = result {
                session.noteExportFailed()
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                Task { await session.importFile(at: url) }
            case .failure:
                session.noteImportFailed()
            }
        }
        .onChange(of: session.selected) { _, device in
            note = device == SyncFixtures.device2 ? "South count" : "North count"
        }
        .task { await session.openIfNeeded() }
    }

    @ViewBuilder private func conflictSection(_ state: RecordState) -> some View {
        if case .conflict(let conflict) = state {
            Section {
                ForEach(conflict.edits) { edit in
                    Button {
                        let id = edit.id
                        Task { await session.choose(id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep \(session.label(for: edit.device))")
                            Text(editSummary(edit))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(session.isWorking)
                    .accessibilityLabel("Keep \(session.label(for: edit.device))'s edit")
                    .accessibilityHint(editSummary(edit))
                }
            } header: {
                Text("Choose an edit")
            } footer: {
                Text("Both edits stay until you choose. Choosing writes a new edit that happened after both.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func beginExport() async {
        guard let data = await session.exportSelected() else { return }
        exportFile = LedgerExchangeFile(data: data)
        isExporting = true
    }

    private func recordSummary(_ state: RecordState) -> String {
        switch state {
        case .absent: "No edit yet"
        case .live(let title, let note): "\(title) — \(note)"
        case .deleted: "Deleted"
        case .conflict: "Edits made apart"
        }
    }

    private func editSummary(_ edit: MutationEnvelope) -> String {
        if edit.kind.isTombstone { return "Deleted" }
        let title = edit.title ?? ""
        let note = edit.note ?? ""
        return "\(title) — \(note)"
    }
}

extension DurableSyncSession {
    func importFile(at url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            await importSelected(data)
        } catch {
            noteImportFailed()
        }
    }
}

/// The manual-exchange file: JSON bytes the ledger already encoded.
struct LedgerExchangeFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// The catalog page's way into the ledger. Shown only on LAB-017's page.
struct DurableSyncLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == DurableSyncExperiment.experimentID {
            #if os(macOS)
            Button {
                window?.destination = .durableSync
            } label: {
                Label("Open \(DurableSyncExperiment.title)", systemImage: DurableSyncExperiment.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌥⌘4)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                DurableSyncPage()
            } label: {
                Label("Open \(DurableSyncExperiment.title)", systemImage: DurableSyncExperiment.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .accessibilityHint("Opens the experiment.")
            #endif
        }
    }
}
