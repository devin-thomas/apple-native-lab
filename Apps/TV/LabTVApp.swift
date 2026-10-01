import SwiftUI

/// The Apple TV host (CORE-013): the catalog, one experiment's record, and Readiness, driven by
/// focus. It carries the catalog, the no-prompt probes, and one experiment module, LAB-031 Native
/// Screening Room, opened from its detail page.
@main
struct LabTVApp: App {
    @State private var host = TVHost.load()

    var body: some Scene {
        WindowGroup {
            TVRootView(host: host)
        }
    }
}

/// Two destinations in the system tab bar. Nothing here intercepts the remote's Menu button, so
/// it keeps its system meaning everywhere: it closes a detail page, then returns focus to the tab
/// bar, then leaves the app for the Home screen.
struct TVRootView: View {
    let host: TVHost

    var body: some View {
        TabView {
            Tab("Catalog", systemImage: "square.grid.2x2") {
                CatalogScreen(host: host)
            }
            Tab("Readiness", systemImage: "gauge.with.dots.needle.33percent") {
                ReadinessScreen(host: host)
            }
        }
    }
}
