import LabCatalog
import SwiftUI
import TypedIntelligence

/// One fixture note as a list row.
struct IntelligenceNoteRow: View {
    let fixture: IntelligenceFixture

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(fixture.title)
            Text(fixture.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the experiment does, above its notes.
struct IntelligenceHeader: View {
    var body: some View {
        Text("Pick a note. Draft a proposal from it with the on-device model, the sample parser, or by hand, then review the change before you apply it.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The notes on iPhone, reached from the experiment's catalog page. There is no tab.
struct IntelligenceNotesScreen: View {
    var body: some View {
        List {
            Section {
                IntelligenceHeader()
            }
            Section("Notes") {
                ForEach(IntelligenceFixture.allCases) { fixture in
                    NavigationLink {
                        TypedIntelligenceView(fixture: fixture)
                    } label: {
                        IntelligenceNoteRow(fixture: fixture)
                    }
                }
            }
        }
        .navigationTitle("Typed Local Intelligence")
    }
}

/// The entry on the experiment's catalog page: pushed on iPhone, the sidebar destination on the Mac.
struct TypedIntelligenceEntry: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == TypedIntelligence.experimentID {
            VStack(alignment: .leading, spacing: 6) {
                #if os(iOS)
                NavigationLink {
                    IntelligenceNotesScreen()
                } label: {
                    Label("Open Typed Local Intelligence", systemImage: "text.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                #else
                Button("Open Typed Local Intelligence", systemImage: "text.badge.checkmark") {
                    window?.destination = .typedIntelligence
                }
                .controlSize(.large)
                .disabled(window == nil)
                #endif
                Text("Runs in this build: the on-device model where the probe finds it available, and the sample parser and manual editor everywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if os(macOS)
/// The Mac content column: the fixture notes, filtered by the window's search.
struct TypedIntelligenceListColumn: View {
    @Bindable var window: MainWindowState

    var body: some View {
        let query = window.searchText.trimmingCharacters(in: .whitespaces)
        let notes = IntelligenceFixture.allCases.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query)
        }
        List(selection: $window.intelligenceNote) {
            Section {
                IntelligenceHeader()
            }
            Section("Notes") {
                ForEach(notes) { fixture in
                    IntelligenceNoteRow(fixture: fixture)
                        .tag(fixture)
                }
            }
        }
        .overlay {
            if notes.isEmpty { ContentUnavailableView.search(text: window.searchText) }
        }
        .navigationTitle("Typed Local Intelligence")
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
    }
}

/// The Mac detail column: the selected note's workbench. Receipts open in the inspector.
struct TypedIntelligenceDetailColumn: View {
    @Bindable var window: MainWindowState

    var body: some View {
        if let fixture = window.intelligenceNote {
            TypedIntelligenceView(fixture: fixture) { record in
                window.inspect(record)
            }
            .id(fixture)
        } else {
            ContentUnavailableView(
                "Select a Note", systemImage: "text.badge.checkmark",
                description: Text("Each note becomes a proposal you review before anything changes.")
            )
        }
    }
}
#endif
