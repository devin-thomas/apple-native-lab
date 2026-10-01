import LabCatalog
import LabDomain
import LabSupport
import Observation
import RenderThatSurvives
import ShareIngress
import SurfaceDeck
import SwiftUI
import TypedIntelligence

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
    /// LAB-004: the demo session, its receipts, and the widget and Control previews.
    case surfaceDeck
    /// LAB-032: render a fixture as a job that survives leaving the app.
    case renderSurvives
    case catalog(CatalogScope)

    var title: String {
        switch self {
        case .collection: "Lab Collection"
        case .actionAtlas: "Action Atlas"
        case .typedIntelligence: "Typed Local Intelligence"
        case .accessSuperpower: AccessSuperpowerExperiment.title
        case .shareInbox: "Share Inbox"
        case .portableObjects: "Portable Objects"
        case .surfaceDeck: SurfaceDeck.title
        case .renderSurvives: RenderThatSurvives.title
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
        case .surfaceDeck: "surface-deck"
        case .renderSurvives: "render-survives"
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
        case ("surface-deck", nil): self = .surfaceDeck
        case ("render-survives", nil): self = .renderSurvives
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
