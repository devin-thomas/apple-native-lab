import LabCatalog
import LabSupport
import SurfaceDeck
import SwiftUI

/// The sidebar: the lab's own collection first, then the catalog by milestone, lifecycle state, and
/// category, each with a count. Every one of the six states is listed, even when it is empty, so
/// the catalog always shows which states exist.
struct SidebarView: View {
    let registry: ExperimentRegistry?
    @Bindable var window: MainWindowState
    @Environment(LabLibrary.self) private var library

    var body: some View {
        List(selection: $window.destination) {
            Section("Lab") {
                Label("Lab Collection", systemImage: "tray.full")
                    .badge(library.census.map { Text("\($0.demo.items)") })
                    .tag(SidebarDestination.collection)
                    .accessibilityLabel(library.census.map { census in
                        "Lab Collection, \(census.demo.items == 1 ? "1 sample" : "\(census.demo.items) samples")"
                    } ?? "Lab Collection")
                    .accessibilityHint("The demo samples stored on this Mac")
                Label("Action Atlas", systemImage: "bolt.horizontal")
                    .tag(SidebarDestination.actionAtlas)
                    .accessibilityHint("Every lab action, the same ones Shortcuts offers")
                Label("Typed Local Intelligence", systemImage: "text.badge.checkmark")
                    .tag(SidebarDestination.typedIntelligence)
                    .accessibilityHint("Turn a note into a proposal you review before anything changes")
                Label(AccessSuperpowerExperiment.title, systemImage: AccessSuperpowerExperiment.symbol)
                    .tag(SidebarDestination.accessSuperpower)
                    .accessibilityHint("One task, finished by sight, VoiceOver, keyboard, or Audio Graph")
                Label("Share Inbox", systemImage: "tray.and.arrow.down")
                    .tag(SidebarDestination.shareInbox)
                    .accessibilityHint("Pasted and chosen files waiting for review")
                Label("Portable Objects", systemImage: "shippingbox")
                    .tag(SidebarDestination.portableObjects)
                    .accessibilityHint("Drag, export, and import lab objects")
                Label(SurfaceDeck.title, systemImage: SurfaceDeck.symbol)
                    .tag(SidebarDestination.surfaceDeck)
                    .accessibilityHint("The demo session, its receipts, and previews of its widget and Control")
                Label(LocalModelBenchExperiment.title, systemImage: LocalModelBenchExperiment.symbol)
                    .tag(SidebarDestination.localModelBench)
                    .accessibilityHint("Compare a fixed corpus. Cold and warm stay separate, and nothing is recorded until you ask.")
            }
            Section("Experiments") {
                row(.all, symbol: "square.grid.2x2")
            }
            Section("Milestones") {
                ForEach(Milestone.allCases, id: \.self) { milestone in
                    row(.milestone(milestone), symbol: "flag")
                }
            }
            Section("States") {
                ForEach(ImplementationState.allCases, id: \.self) { state in
                    row(.state(state), symbol: state.symbolName)
                        .help(state.meaning)
                }
            }
            Section("Categories") {
                ForEach(registry?.categories ?? [], id: \.self) { category in
                    row(.category(category), symbol: "folder")
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
    }

    private func row(_ scope: CatalogScope, symbol: String) -> some View {
        let count = registry?.count(in: scope) ?? 0
        // A text badge shows zero too, so an empty state still reads as empty rather than missing.
        return Label(scope.title, systemImage: symbol)
            .badge(Text("\(count)"))
            .tag(SidebarDestination.catalog(scope))
            .accessibilityLabel("\(scope.title), \(count == 1 ? "1 experiment" : "\(count) experiments")")
    }
}
