import ContextCards
import AudioWorkshop
import LabCatalog
import LabDomain
import LabSupport
import Observation
import RenderThatSurvives
import ScreeningRoom
import ShareIngress
import RespectfulAttention
import ShortcutWorkbench
import SurfaceDeck
import SwiftUI
import TactileGrammar
import TabletopReality
import TypedIntelligence
import FindTheThing

/// What the sidebar selects: the lab's own data, or a slice of the experiment catalog.
enum SidebarDestination: Hashable {
    case collection
    /// LAB-001: every Action Atlas action, runnable without Siri or Shortcuts.
    case actionAtlas
    /// LAB-010: typed proposals from a note, reviewed before anything changes.
    case typedIntelligence
    /// LAB-035: one task, finished by sight, VoiceOver, keyboard, or Audio Graph.
    case accessSuperpower
    /// LAB-007: the share inbox, with the paste and file-picker fallbacks.
    case shareInbox
    /// LAB-008: drag, export, and import lab objects.
    case portableObjects
    /// LAB-041: local authorization, a scoped secret, and a passkey simulation.
    case trustDesk
    /// LAB-016: continue a draft at a section. The hint is an identifier and a position.
    case pickUpHere
    /// LAB-002: one sample on screen, and the decision to set it aside.
    case contextCards
    /// LAB-009: browse sample documents and previews without the File Provider.
    case documentsEverywhere
    /// LAB-004: the demo session, its receipts, and the widget and Control previews.
    case surfaceDeck
    /// LAB-042: command palette, notes, and menu-bar status. Mac only.
    case desktopPower
    /// LAB-015: cold and warm fixture runs, recorded only when asked.
    case localModelBench
    /// LAB-017: two devices, a local ledger, and a manual document.
    case durableSync
    /// LAB-030: three tactile cues, their visual and spoken equivalents, and device feedback.
    case tactileGrammar
    /// LAB-043: the agenda, its timers, and lab-owned alerts.
    case respectfulAttention
    /// LAB-012: a chosen image becomes a reviewable record.
    case pointInspect
    /// LAB-013: a transcript scrubbed against its audio, with provisional and finalized text.
    case speechTimeline
    /// LAB-006: search opted-in records and see which ones the answer used.
    case findTheThing
    /// LAB-003: curated App Shortcuts, recipes, and the manual fallback.
    case shortcutWorkbench
    /// LAB-032: render a fixture as a job that survives leaving the app.
    case renderSurvives
    /// LAB-031: watch the test card, move it between surfaces, and resume.
    case screeningRoom
    /// LAB-029: the audio graph, its safety controls, MIDI, offline processing, and presets.
    case audioWorkshop
    /// LAB-023: the virtual table, its object list, and the tracking gate.
    case tabletopReality
    case catalog(CatalogScope)

    var title: String {
        switch self {
        case .collection: "Lab Collection"
        case .actionAtlas: "Action Atlas"
        case .typedIntelligence: "Typed Local Intelligence"
        case .accessSuperpower: AccessSuperpowerExperiment.title
        case .shareInbox: "Share Inbox"
        case .portableObjects: "Portable Objects"
        case .trustDesk: TrustDeskExperiment.title
        case .pickUpHere: "Pick Up Here"
        case .contextCards: ContextCards.title
        case .documentsEverywhere: "Documents Everywhere"
        case .surfaceDeck: SurfaceDeck.title
        case .desktopPower: "Desktop Native Power"
        case .localModelBench: LocalModelBenchExperiment.title
        case .durableSync: DurableSyncExperiment.title
        case .tactileGrammar: TactileGrammarExperiment.title
        case .respectfulAttention: RespectfulAttention.title
        case .pointInspect: "Point, Inspect, Propose"
        case .speechTimeline: "Speech Timeline"
        case .findTheThing: FindTheThing.title
        case .shortcutWorkbench: ShortcutWorkbench.title
        case .renderSurvives: RenderThatSurvives.title
        case .screeningRoom: ScreeningRoom.title
        case .audioWorkshop: AudioWorkshop.title
        case .tabletopReality: TabletopExperiment.title
        case .catalog(let scope): scope.title
        }
    }

    /// A short string for scene storage. It holds no content, only which list was showing.
    var storageKey: String {
        switch self {
        case .collection: "collection"
        case .actionAtlas: "action-atlas"
        case .typedIntelligence: "typed-intelligence"
        case .accessSuperpower: "access-superpower"
        case .shareInbox: "share-inbox"
        case .portableObjects: "portable-objects"
        case .trustDesk: "trust-desk"
        case .pickUpHere: "pick-up-here"
        case .contextCards: "context-cards"
        case .documentsEverywhere: "documents-everywhere"
        case .surfaceDeck: "surface-deck"
        case .desktopPower: "desktop-power"
        case .localModelBench: "local-model-bench"
        case .durableSync: "durable-sync"
        case .tactileGrammar: "tactile-grammar"
        case .respectfulAttention: "respectful-attention"
        case .pointInspect: "point-inspect"
        case .speechTimeline: "speech-timeline"
        case .findTheThing: "find-the-thing"
        case .shortcutWorkbench: "shortcut-workbench"
        case .renderSurvives: "render-survives"
        case .screeningRoom: "screening-room"
        case .audioWorkshop: "audio-workshop"
        case .tabletopReality: "tabletop-reality"
        case .catalog(.all): "all"
        case .catalog(.milestone(let milestone)): "milestone:\(milestone.rawValue)"
        case .catalog(.category(let category)): "category:\(category)"
        case .catalog(.state(let state)): "state:\(state.rawValue)"
        }
    }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count == 2 ? parts[1] : nil) {
        case ("collection", nil): self = .collection
        case ("action-atlas", nil): self = .actionAtlas
        case ("typed-intelligence", nil): self = .typedIntelligence
        case ("access-superpower", nil): self = .accessSuperpower
        case ("share-inbox", nil): self = .shareInbox
        case ("portable-objects", nil): self = .portableObjects
        case ("trust-desk", nil): self = .trustDesk
        case ("pick-up-here", nil): self = .pickUpHere
        case ("context-cards", nil): self = .contextCards
        case ("documents-everywhere", nil): self = .documentsEverywhere
        case ("surface-deck", nil): self = .surfaceDeck
        case ("desktop-power", nil): self = .desktopPower
        case ("local-model-bench", nil): self = .localModelBench
        case ("durable-sync", nil): self = .durableSync
        case ("tactile-grammar", nil): self = .tactileGrammar
        case ("respectful-attention", nil): self = .respectfulAttention
        case ("point-inspect", nil): self = .pointInspect
        case ("speech-timeline", nil): self = .speechTimeline
        case ("find-the-thing", nil): self = .findTheThing
        case ("shortcut-workbench", nil): self = .shortcutWorkbench
        case ("render-survives", nil): self = .renderSurvives
        case ("screening-room", nil): self = .screeningRoom
        case ("audio-workshop", nil): self = .audioWorkshop
        case ("tabletop-reality", nil): self = .tabletopReality
        case ("all", nil): self = .catalog(.all)
        case ("milestone", let raw?): guard let milestone = Milestone(rawValue: raw) else { return nil }
            self = .catalog(.milestone(milestone))
        case ("category", let name?): self = .catalog(.category(name))
        case ("state", let raw?): guard let state = ImplementationState(rawValue: raw) else { return nil }
            self = .catalog(.state(state))
        default: return nil
        }
    }
}

/// One main window's navigation and presentation state. Menu commands reach the frontmost window's
/// state through `FocusedValues.mainWindow`.
@MainActor
@Observable
final class MainWindowState {
    var destination: SidebarDestination? = .catalog(.milestone(.m1))
    var experimentID: RegisteredExperiment.ID?
    var itemID: ItemID?
    /// The Action Atlas action whose form the detail column shows.
    var atlasAction: AtlasAction?
    /// The Typed Local Intelligence note whose workbench the detail column shows.
    var intelligenceNote: IntelligenceFixture?
    /// Access as a Superpower's selection and result in this window.
    let access = AccessTaskSession()
    /// The share-inbox import the detail column shows.
    var inboxEntry: InboxEntry.ID?
    /// LAB-008: this window's objects, selection, and import under review.
    let portableObjects = PortableObjectsSession()
    /// LAB-041: this window's identity, grant, and passkey simulation.
    let trustDesk = TrustDeskSession()
    /// LAB-016: this window's continuation. Clearing it drops the hint, not the drafts.
    let pickUp = PickUpSession()
    /// LAB-002: the sample on screen and the decision waiting on it.
    let contextCards = ContextCardsSession()
    /// LAB-015: this window's bench runs. Nothing is recorded until Record Selected Run.
    let bench = LocalModelBenchSession()
    /// LAB-017: this window's two-device ledger replay.
    let durableSync = DurableSyncSession()
    /// LAB-030: this window's cues, intensity, and last result.
    let tactile = TactileGrammarModel()
    /// LAB-006: the shelf search and its answer, over the app index.
    let finder = FindTheThingSession()
    /// LAB-003: selected recipe in the workbench list.
    var workbenchRecipeID: RecipeID?
    /// LAB-009: sample documents, previews, and adopt-into-lab.
    let documentsEverywhere = DocumentsEverywhereSession()
    /// LAB-023: this window's table, selection, and tracking.
    let tabletop = TabletopSession()
    var searchText = ""
    /// Incremented to ask the window to focus its search field.
    var searchRequests = 0
    var showsInspector = false
    /// The receipt the inspector shows; `nil` means the newest one.
    var inspectedReceiptID: OperationID?
    var isConfirmingReset = false

    func focusSearch() { searchRequests += 1 }

    func showCollection() { destination = .collection }

    /// Opens the inspector on a receipt that just arrived.
    func inspect(_ record: ReceiptRecord) {
        inspectedReceiptID = record.id
        showsInspector = true
    }
}

extension FocusedValues {
    @Entry var mainWindow: MainWindowState?
}
