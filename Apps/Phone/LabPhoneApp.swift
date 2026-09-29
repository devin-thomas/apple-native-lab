import SwiftUI

@main
struct LabPhoneApp: App {
    @State private var model = LabModel()
    @State private var library = LabLibrary()

    var body: some Scene {
        WindowGroup {
            PhoneRootView(model: model)
                .environment(library)
                .task { await library.start() }
        }
    }
}

/// Four tabs, each with its own navigation stack: the catalog, the lab's own collection, the
/// import entry point, and Readiness.
struct PhoneRootView: View {
    let model: LabModel

    var body: some View {
        TabView {
            Tab("Catalog", systemImage: "square.grid.2x2") {
                CatalogTab(model: model)
            }
            Tab("Collection", systemImage: "tray.full") {
                CollectionTab()
            }
            Tab("Import", systemImage: "square.and.arrow.down") {
                ImportTab(model: model)
            }
            Tab("Readiness", systemImage: "gauge.with.dots.needle.33percent") {
                NavigationStack { ReadinessView(model: model) }
            }
        }
    }
}
