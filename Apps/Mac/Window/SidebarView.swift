import ContextCards
import LabCatalog
import LabSupport
import RespectfulAttention
import SurfaceDeck
import SwiftUI
import TactileGrammar

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
                Label(TrustDeskExperiment.title, systemImage: TrustDeskExperiment.symbol)
                    .tag(SidebarDestination.trustDesk)
                    .accessibilityHint("Authorize a sealed record, and compare that with a passkey simulation")
                Label("Pick Up Here", systemImage: "arrow.left.arrow.right")
                    .tag(SidebarDestination.pickUpHere)
                    .accessibilityHint("Continue a draft at a section, or copy a link or the document")
                Label(ContextCards.title, systemImage: ContextCards.symbol)
                    .tag(SidebarDestination.contextCards)
                    .accessibilityHint("Ask about the sample on screen, then set it aside")
                Label(SurfaceDeck.title, systemImage: SurfaceDeck.symbol)
                    .tag(SidebarDestination.surfaceDeck)
                    .accessibilityHint("The demo session, its receipts, and previews of its widget and Control")
                Label("Desktop Native Power", systemImage: "macwindow")
                    .tag(SidebarDestination.desktopPower)
                    .accessibilityHint("Command palette, notes, and the menu-bar status")
                Label(LocalModelBenchExperiment.title, systemImage: LocalModelBenchExperiment.symbol)
                    .tag(SidebarDestination.localModelBench)
                    .accessibilityHint("Compare a fixed corpus. Cold and warm stay separate, and nothing is recorded until you ask.")
                Label(DurableSyncExperiment.title, systemImage: DurableSyncExperiment.symbol)
                    .tag(SidebarDestination.durableSync)
                    .accessibilityHint("Two devices, a local ledger, and a document you can exchange by hand")
                Label(TactileGrammarExperiment.title, systemImage: TactileGrammarExperiment.symbol)
                    .tag(SidebarDestination.tactileGrammar)
                    .accessibilityHint("Success, warning, and timing cues, with a visual pulse when haptics are missing")
                Label(RespectfulAttention.title, systemImage: RespectfulAttention.symbol)
                    .tag(SidebarDestination.respectfulAttention)
                    .accessibilityHint("A reminder, a Focus filter, and an alarm, scheduled only when you ask")
                Label("Point, Inspect, Propose", systemImage: "viewfinder")
                    .tag(SidebarDestination.pointInspect)
                    .accessibilityHint("Turn a chosen image into a record you review before it is saved")
                Label("Speech Timeline", systemImage: "waveform.and.magnifyingglass")
                    .tag(SidebarDestination.speechTimeline)
                    .accessibilityHint("Transcribe on this device and scrub the text against its audio")
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
