import SwiftUI

@main
struct LabMacApp: App {
    @State private var model = LabModel()
    @State private var library: LabLibrary

    init() {
        let library = LabLibrary()
        _library = State(initialValue: library)
        // App Intents use this same library, so their receipts join this session's list.
        ActionAtlasHost.connect(library)
        SurfaceDeckHost.connect(library)
    }

    var body: some Scene {
        WindowGroup("Native Lab", id: "catalog") {
            MainWindow(model: model)
                .environment(library)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            LabCommands(library: library)
        }

        // One Readiness window; its shortcut also appears in the Window menu.
        Window("Readiness", id: "readiness") {
            ReadinessView(model: model)
                .frame(minWidth: 460, minHeight: 520)
        }
        .defaultSize(width: 520, height: 720)
        .keyboardShortcut("0", modifiers: [.command, .shift])

        Settings {
            SettingsView()
                .environment(library)
        }
    }
}
