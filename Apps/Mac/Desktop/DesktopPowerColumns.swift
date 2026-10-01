import DesktopNativePower
import LabCatalog
import SwiftUI
import UniformTypeIdentifiers

/// The content column: the status the menu bar also shows, the commands, and the notes.
struct DesktopPowerListColumn: View {
    @Environment(DesktopPowerSession.self) private var session
    @Environment(MainWindowState.self) private var window

    var body: some View {
        @Bindable var desktop = session
        List(selection: $desktop.selectedID) {
            Section {
                Text(session.status.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Desktop status, \(session.status.summary)")
                Toggle("Private note", isOn: $desktop.importingPrivate)
                    .help("A private note is kept, and a later launch does not open its window.")
            }
            Section("Notes") {
                if filtered.isEmpty {
                    Text("No notes yet. Import selected text, or import a text file.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { note in
                    DesktopNoteRow(note: note)
                        .tag(note.id)
                        .onTapGesture(count: 2) { session.open(note.id) }
                        .contextMenu {
                            Button(DesktopCommand.openDocumentWindow.title) { session.open(note.id) }
                        }
                }
            }
        }
        .navigationTitle("Desktop Native Power")
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        .toolbar {
            ToolbarItemGroup {
                Button(DesktopCommand.openDocumentWindow.title) { session.openSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.selectedID == nil)
                Button(DesktopCommand.showPalette.title) { session.showsPalette = true }
            }
        }
        .task {
            await session.reload()
            session.restore(storageKey: storedRoutes)
        }
        .onChange(of: session.openWindowCount) { storedRoutes = session.restorableKey() }
    }

    @SceneStorage("desktop-routes") private var storedRoutes = ""

    private var filtered: [DesktopDocument] {
        let needle = window.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return session.notes }
        return session.notes.filter {
            $0.title.localizedStandardContains(needle) || $0.body.localizedStandardContains(needle)
        }
    }
}

private struct DesktopNoteRow: View {
    let note: DesktopDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
            Text(note.privacy == .privateContent ? "Private · \(origin)" : origin)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens in a new window. Double-click, or press Return.")
    }

    private var origin: String {
        switch note.origin {
        case .fixture: "Fixture preview"
        case .fileImport: "File import"
        case .selectedText: "Selected text"
        case .script: "Allowlisted command"
        }
    }
}

/// The detail column: the selected note, when it may be shown, and how this build runs the experiment.
struct DesktopPowerDetailColumn: View {
    @Environment(DesktopPowerSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let failure = session.failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.primary)
                }
                if let summary = session.lastSummary {
                    Text(summary)
                        .font(.callout)
                }
                if let note = session.notes.first(where: { $0.id == session.selectedID }) {
                    noteBody(note)
                } else {
                    ContentUnavailableView(
                        "No Note Selected",
                        systemImage: "macwindow",
                        description: Text("Import a note, or choose one in the list. File › Import Desktop Note… reads a text file.")
                    )
                }
                howItWorks
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func noteBody(_ note: DesktopDocument) -> some View {
        Text(note.title).font(.title2)
        Text(note.privacy == .privateContent ? "Private note" : "Note")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        if session.shouldPresent(note.id) {
            Text(note.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label("This private note stays closed until you open it.", systemImage: "lock")
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How this works").font(.headline)
            Text("Menus, the command palette, the Services menu, and the Run Desktop Command intent all call one station. Importing a note commits it through the lab’s operation service and leaves a receipt. The intent can only import the bundled fixture or report status. It does not run shell text. Closing a window leaves the note in place. A private note is not opened again from a restored scene.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DesktopPaletteSheet: View {
    @Environment(DesktopPowerSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var session = session
        NavigationStack {
            List(session.palette) { entry in
                Button {
                    Task {
                        await session.run(entry.command)
                        if entry.command != .showPalette { dismiss() }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                        Text("\(entry.menuPath) · \(entry.shortcut)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $session.paletteQuery, prompt: "Commands")
            .navigationTitle("Command Palette")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .onChange(of: session.paletteQuery) { session.refresh() }
    }
}

/// A document window. Its text is shown only when the station says this session may present it.
struct DesktopDocumentWindow: View {
    let documentID: String?
    @Environment(DesktopPowerSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let note, session.shouldPresent(note.id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(note.title).font(.title2)
                    Text(note.body).textSelection(.enabled)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(note.title)
        } else {
            ContentUnavailableView(
                "This note stays closed",
                systemImage: "lock",
                description: Text("Open it from Desktop Native Power. A private note is not restored into a window.")
            )
            .task { dismiss() }
        }
    }

    private var note: DesktopDocument? {
        guard let documentID else { return nil }
        return session.notes.first { $0.id.rawValue == documentID }
    }
}

/// Palette sheet, file import, and document windows for the desktop station. Attached to the main window.
struct DesktopPowerChrome: ViewModifier {
    @Environment(DesktopPowerSession.self) private var session
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        @Bindable var session = session
        content
            .onAppear { DesktopServiceProvider.install() }
            .onChange(of: session.pendingDocumentID) { _, id in
                guard let id else { return }
                openWindow(id: "desktop-document", value: id)
                session.pendingDocumentID = nil
            }
            .sheet(isPresented: $session.showsPalette) {
                DesktopPaletteSheet()
                    .environment(session)
            }
            .fileImporter(
                isPresented: $session.showsFileImporter,
                allowedContentTypes: [.plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                Task { await session.importFileResult(result) }
            }
    }
}

/// Menu-bar status. It repeats the window's count and the same commands; it is not the only path.
struct DesktopMenuBarMenu: View {
    var session: DesktopPowerSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(session.status.summary)
        Button("Open Desktop Native Power") { openWindow(id: "catalog") }
        Button(DesktopCommand.importSelectedText.title) {
            Task { await session.importPasteboard() }
        }
        Button(DesktopCommand.importFile.title) { session.showsFileImporter = true }
        Button(DesktopCommand.showPalette.title) {
            session.showsPalette = true
            openWindow(id: "catalog")
        }
    }
}

/// The catalog page's way into this experiment. Mac only; the type lives in the Mac target.
struct DesktopPowerLaunch: View {
    let experiment: RegisteredExperiment

    @Environment(MainWindowState.self) private var window

    var body: some View {
        if experiment.id == "LAB-042" {
            Button {
                window.destination = .desktopPower
            } label: {
                Label("Open Desktop Native Power", systemImage: "macwindow")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Command palette, notes, and the menu-bar status (⌘9)")
        }
    }
}
