import LabCatalog
import ModelRouting
import SwiftUI

/// Model Routing Observatory on one scrollable page (iPhone pushes it; Mac uses columns).
struct ModelRoutingPage: View {
    @Environment(LabLibrary.self) private var library
    @State private var session = ModelRoutingSession()

    var body: some View {
        ModelRoutingPageContent(session: session)
            .overlay {
                if library.collections.isEmpty { LibraryPhaseView() }
            }
            .task { await session.start(with: library) }
    }
}

/// Catalog-page entry for LAB-011.
struct ModelRoutingLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == ModelRoutingExperiment.id {
            VStack(alignment: .leading, spacing: 6) {
                #if os(macOS)
                Button {
                    window?.destination = .modelRouting
                } label: {
                    Label("Open \(ModelRoutingExperiment.title)", systemImage: ModelRoutingExperiment.symbol)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: 8))
                .disabled(window == nil)
                .help("Show the experiment in this window (⌘9)")
                .accessibilityHint("Shows the experiment in this window.")
                #else
                NavigationLink {
                    ModelRoutingPage()
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Open \(ModelRoutingExperiment.title)", systemImage: ModelRoutingExperiment.symbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .accessibilityHint("Opens the experiment.")
                #endif
                Text("Runs in this build: local-only by default, PCC eligibility explained separately from on-device availability, outgoing fields before any cloud attempt, and local or manual fallback without a third-party key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
