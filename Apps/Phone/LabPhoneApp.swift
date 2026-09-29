import SwiftUI

@main
struct LabPhoneApp: App {
    @State private var model = LabModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Catalog", systemImage: "square.grid.2x2") {
                    CatalogListView(model: model)
                }
                Tab("Readiness", systemImage: "gauge.with.dots.needle.33percent") {
                    NavigationStack { ReadinessView(model: model) }
                }
            }
        }
    }
}
