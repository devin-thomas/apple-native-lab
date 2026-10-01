import LabJobs
import SwiftUI
import TactileGrammar

@main
struct LabMacApp: App {
    @State private var model = LabModel()
    @State private var library: LabLibrary
    @State private var desktop: DesktopPowerSession

    init() {
        let library = LabLibrary()
        _library = State(initialValue: library)
        // App Intents use this same library, so their receipts join this session's list.
        ActionAtlasHost.connect(library)
        SurfaceDeckHost.connect(library)
        let desktop = DesktopPowerHost.connect(library)
        _desktop = State(initialValue: desktop)
        ContextCardsHost.connect(library)
        TactileGrammarCenter.shared.install(LiveTactileGrammar.makeEngine())
        AttentionHost.connect(library)
        FindTheThingHost.connect()
        ShortcutWorkbenchHost.connect(library)
        // LAB-032: the Mac worker runs renders while the app runs.
        RenderStudioModel.shared.connect(library, runway: MacWorkerRunway())
    }

    var body: some Scene {
        WindowGroup("Native Lab", id: "catalog") {
            MainWindow(model: model)
                .environment(library)
                .environment(desktop)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            LabCommands(library: library, desktop: desktop)
        }

        MenuBarExtra("Desktop Native Power", systemImage: "macwindow") {
            DesktopMenuBarMenu(session: desktop)
        }

        WindowGroup("Desktop Note", id: "desktop-document", for: String.self) { documentID in
            DesktopDocumentWindow(documentID: documentID.wrappedValue)
                .environment(library)
                .environment(desktop)
                .frame(minWidth: 360, minHeight: 240)
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
