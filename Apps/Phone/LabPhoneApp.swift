import SwiftUI
import TactileGrammar

@main
struct LabPhoneApp: App {
    @State private var model = LabModel()
    @State private var library: LabLibrary

    init() {
        let library = LabLibrary()
        _library = State(initialValue: library)
        // App Intents use this same library, so their receipts join this session's list.
        ActionAtlasHost.connect(library)
        SurfaceDeckHost.connect(library)
        ContextCardsHost.connect(library)
        TactileGrammarCenter.shared.install(LiveTactileGrammar.makeEngine())
        AttentionHost.connect(library)
        FindTheThingHost.connect()
        ShortcutWorkbenchHost.connect(library)
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView(model: model)
                // Inside the library's environment: the deck it presents reads the library.
                .surfaceDeckPresenter()
                .environment(library)
                .task { await library.start() }
        }
    }
}

/// Five tabs, each with its own navigation stack: the catalog, the lab's own collection, the
/// Action Atlas action browser, the import entry point, and Readiness.
struct PhoneRootView: View {
    let model: LabModel
    @Environment(LabLibrary.self) private var library
    @State private var pickUp = PickUpSession()

    var body: some View {
        TabView {
            Tab("Catalog", systemImage: "square.grid.2x2") {
                CatalogTab(model: model)
            }
            Tab("Collection", systemImage: "tray.full") {
                CollectionTab()
            }
            Tab("Actions", systemImage: "bolt.horizontal") {
                ActionsTab()
            }
            Tab("Import", systemImage: "square.and.arrow.down") {
                ImportTab(model: model)
            }
            Tab("Readiness", systemImage: "gauge.with.dots.needle.33percent") {
                NavigationStack { ReadinessView(model: model) }
            }
        }
        .environment(pickUp)
        .pickUpContinuation(session: pickUp, library: library) {}
    }
}
