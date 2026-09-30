import LabDomain
import ShareIngress
import SwiftUI
import UniformTypeIdentifiers

/// The content column for the share inbox (LAB-007): Paste (⌘V or the button), Choose Files,
/// and files dropped on the list stage into the inbox; each waiting import opens in the detail
/// column. The Mac has no share extension; these are its import paths.
struct ShareInboxListColumn: View {
    @Bindable var window: MainWindowState
    @State private var inbox = ShareInboxModel.shared
    @State private var isChoosingFiles = false
    @State private var isTargeted = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let entries = inbox.snapshot.entries.filter { matches($0) }
        List(selection: $window.inboxEntry) {
            Section {
                HStack {
                    InboxIntakeControls(model: inbox, isChoosingFiles: $isChoosingFiles)
                }
                InboxIntakeStatus(model: inbox)
                if !inbox.canChooseFiles {
                    Text("Choose Files needs the user-selected file read entitlement, which this Mac build doesn't carry. Copy files in the Finder and paste them here, or drag them onto this list.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                InboxLimitsText(limits: inbox.limits)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Add to the inbox")
            }
            Section("Waiting for review") {
                if inbox.snapshot.entries.isEmpty {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(entries) { entry in
                    InboxEntryRow(entry: entry)
                        .tag(entry.id)
                }
            }
            if !inbox.snapshot.quarantined.isEmpty {
                Section("Set aside") {
                    ForEach(inbox.snapshot.quarantined) { entry in
                        QuarantineRow(entry: entry, model: inbox)
                    }
                }
            }
            Section("Sharing from other apps") {
                Text("The Mac has no share extension yet. Copy something in another app and paste it here, or drag files onto this list.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.tint, lineWidth: 3)
                    .accessibilityHidden(true)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty, inbox.canImport else { return false }
            inbox.drop(files)
            return true
        } isTargeted: { isTargeted = $0 }
        .onPasteCommand(of: ShareInboxTypes.pasteable) { providers in
            inbox.paste(providers)
        }
        .fileImporter(isPresented: $isChoosingFiles, allowedContentTypes: ShareInboxTypes.choosable, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result, !urls.isEmpty { inbox.importFiles(urls) }
        }
        .navigationTitle("Share Inbox")
        .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        .task {
            await inbox.start()
            await inbox.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await inbox.refresh() } }
        }
    }

    private func matches(_ entry: InboxEntry) -> Bool {
        let needle = window.searchText.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty || entry.headline.localizedStandardContains(needle) || entry.kindTitle.localizedStandardContains(needle)
    }

    private var emptyText: String {
        switch inbox.phase {
        case .unavailable(let reason): reason
        case .notStarted, .opening: "Opening the inbox…"
        case .ready: inbox.canChooseFiles
            ? "Nothing is waiting. Paste, choose files, or drop files here."
            : "Nothing is waiting. Paste, or drop files here."
        }
    }
}

/// The detail column for the share inbox: the selected import's review screen. An adoption's
/// receipt opens in the window's receipt inspector.
struct ShareInboxDetailColumn: View {
    @Bindable var window: MainWindowState
    @State private var inbox = ShareInboxModel.shared

    var body: some View {
        if let id = window.inboxEntry, let entry = inbox.snapshot.entry(id) ?? inbox.added[id]?.entry {
            InboxEntryDetail(entry: entry, model: inbox) { record in
                window.inspect(record)
            }
            .id(id)
        } else {
            ContentUnavailableView(
                "Select an Import", systemImage: "tray.and.arrow.down",
                description: Text("Each import waits here until you add it to one of your collections or remove it.")
            )
        }
    }
}
