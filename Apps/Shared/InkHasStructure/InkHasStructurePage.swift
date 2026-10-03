import InkHasStructure
import LabCatalog
import SwiftUI

/// Ink Has Structure on one page for iPhone: open the sample, draw (mouse/touch or PencilKit any
/// input), type a note, undo/erase, export a flattened preview, and save through the operation
/// service.
struct InkHasStructurePage: View {
    @Environment(LabLibrary.self) private var library
    @State private var session = InkSession()

    var body: some View {
        ScrollView {
            InkWorkbench(session: session, onSave: save, usesPencilKitInput: true)
                .padding(16)
        }
        .navigationTitle(InkHasStructureExperiment.title)
        .task {
            if session.document == nil { await session.openSample() }
        }
        .overlay {
            if library.phase != .ready && library.collections.isEmpty { LibraryPhaseView() }
        }
    }

    private func save() {
        Task { _ = await session.save(in: library) }
    }
}

/// Catalog entry for LAB-045.
struct InkHasStructureLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == InkHasStructureExperiment.id {
            #if os(macOS)
            Button {
                window?.destination = .inkHasStructure
            } label: {
                Label("Open \(InkHasStructureExperiment.title)", systemImage: InkHasStructureExperiment.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌃⌥⌘2)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                InkHasStructurePage()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(InkHasStructureExperiment.title)", systemImage: InkHasStructureExperiment.symbol)
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
