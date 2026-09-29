import LabCatalog
import SwiftUI

@main
struct LabMacApp: App {
    @State private var model = LabModel()

    var body: some Scene {
        WindowGroup("Native Lab", id: "catalog") {
            CatalogSplitView(model: model)
                .frame(minWidth: 900, minHeight: 540)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            LabCommands()
        }

        Window("Readiness", id: "readiness") {
            ReadinessView(model: model)
                .frame(minWidth: 460, minHeight: 520)
        }
        .keyboardShortcut("0", modifiers: [.command, .shift])
    }
}

private struct LabCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Readiness") { openWindow(id: "readiness") }
                .keyboardShortcut("0", modifiers: [.command, .shift])
        }
    }
}
