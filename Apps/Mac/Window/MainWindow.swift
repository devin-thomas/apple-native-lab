import LabCatalog
import SwiftUI

/// The main window: sidebar, content, and detail columns, with the receipt inspector on the
/// trailing edge. Its state is per window, so two windows can browse different places.
struct MainWindow: View {
    let model: LabModel
    @State private var window = MainWindowState()
    // Only which list and which experiment were showing; never data content.
    @SceneStorage("destination") private var storedDestination = ""
    @SceneStorage("experiment") private var storedExperiment = ""
    @FocusState private var focusedPane: WindowPane?
    @Environment(LabLibrary.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            SidebarView(registry: model.registry, window: window)
                .focused($focusedPane, equals: .sidebar)
        } content: {
            contentColumn
                .focused($focusedPane, equals: .results)
        } detail: {
            // The inspector belongs to the detail column; attached to the whole split view it
            // pushed the columns past the window's edges.
            detailColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 520)
                .inspector(isPresented: $window.showsInspector) {
                    ReceiptInspector(window: window, focusedPane: $focusedPane)
                        // Escape leaves the inspector for the results, from any control in it.
                        .onExitCommand { focusedPane = .results }
                }
        }
        .searchable(text: $window.searchText, placement: .sidebar, prompt: searchPrompt)
        .searchFocused($focusedPane, equals: .search)
        .onKeyPress(.tab, phases: .down) { press in
            guard !press.modifiers.contains(.shift), let pane = focusedPane else { return .ignored }
            focusedPane = pane.next(receiptsShowing: window.showsReceiptList(in: library))
            return .handled
        }
        .toolbar {
            ToolbarItem {
                Button("Readiness", systemImage: "gauge.with.dots.needle.33percent") {
                    openWindow(id: "readiness")
                }
                .help("Show this build and device (⇧⌘0)")
            }
            ToolbarItem {
                Button {
                    window.showsInspector.toggle()
                } label: {
                    Label(window.showsInspector ? "Hide Receipts" : "Show Receipts", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the receipt inspector (⌥⌘I)")
            }
        }
        .resetDemoConfirmation(isPresented: $window.isConfirmingReset) { record in
            window.inspect(record)
        }
        .focusedSceneValue(\.mainWindow, window)
        // Views in the window, such as an experiment page's Open button, change its destination (LAB-010, LAB-035).
        .environment(window)
        .environment(\.openPortableObjects, OpenPortableObjectsAction(window: ObjectIdentifier(window)) { window.destination = .portableObjects })
        .onChange(of: window.searchRequests) { focusedPane = .search }
        .onChange(of: window.destination) { old, new in
            if (old == .collection) != (new == .collection) { window.searchText = "" }
            // The detail column shows only an experiment the new list contains.
            if case .catalog(let scope) = new, let id = window.experimentID,
               let experiment = model.registry?.experiment(id: id), !scope.contains(experiment) {
                window.experimentID = nil
            }
            storedDestination = new?.storageKey ?? ""
        }
        .onChange(of: window.experimentID) { _, new in storedExperiment = new ?? "" }
        .onAppear(perform: restore)
        // The Open Surface Deck action (Shortcuts) shows the deck in this window (LAB-004).
        .onChange(of: SurfaceDeckModel.shared.openRequests) { window.destination = .surfaceDeck }
        .task { await library.start() }
    }

    @ViewBuilder private var contentColumn: some View {
        switch window.destination {
        case .collection:
            CollectionListColumn(window: window)
        case .actionAtlas:
            ActionAtlasListColumn(window: window)
        case .typedIntelligence:
            TypedIntelligenceListColumn(window: window)
        case .accessSuperpower:
            AccessSuperpowerListColumn(window: window, session: window.access)
        case .shareInbox:
            ShareInboxListColumn(window: window)
        case .portableObjects:
            PortableObjectsListColumn(window: window)
        case .surfaceDeck:
            SurfaceDeckListColumn(window: window)
        case .tactileGrammar:
            TactileGrammarListColumn(model: window.tactile)
        case .catalog(let scope):
            if let registry = model.registry {
                CatalogListColumn(registry: registry, scope: scope, window: window)
            } else {
                registryUnavailable
            }
        case nil:
            ContentUnavailableView("Choose a List", systemImage: "sidebar.left",
                                   description: Text("Pick the lab collection or a slice of the catalog in the sidebar."))
        }
    }

    @ViewBuilder private var detailColumn: some View {
        switch window.destination {
        case .collection:
            CollectionDetailColumn(itemID: window.itemID)
        case .actionAtlas:
            ActionAtlasDetailColumn(window: window)
        case .typedIntelligence:
            TypedIntelligenceDetailColumn(window: window)
        case .accessSuperpower:
            AccessSuperpowerDetailColumn(window: window, session: window.access)
        case .shareInbox:
            ShareInboxDetailColumn(window: window)
        case .portableObjects:
            PortableObjectsDetailColumn(window: window)
        case .surfaceDeck:
            SurfaceDeckDetailColumn()
        case .tactileGrammar:
            TactileGrammarDetailColumn(model: window.tactile)
        case .catalog:
            if let registry = model.registry {
                CatalogDetailColumn(registry: registry, experimentID: window.experimentID)
            } else {
                registryUnavailable
            }
        case nil:
            Color.clear
        }
    }

    private var registryUnavailable: some View {
        ContentUnavailableView("Catalog Unavailable", systemImage: "exclamationmark.triangle",
                               description: Text(model.registryError ?? "The experiment registry did not load."))
    }

    private var searchPrompt: String {
        switch window.destination {
        case .collection: "Search samples"
        case .actionAtlas: "Search actions"
        case .typedIntelligence: "Search notes"
        case .accessSuperpower: "Search archived samples"
        case .shareInbox: "Search the inbox"
        case .portableObjects: "Search objects"
        case .tactileGrammar: "Search cues"
        default: "Search experiments"
        }
    }

    private func restore() {
        if let destination = SidebarDestination(storageKey: storedDestination) {
            window.destination = destination
        }
        if !storedExperiment.isEmpty, model.registry?.experiment(id: storedExperiment) != nil {
            window.experimentID = storedExperiment
        }
    }
}
