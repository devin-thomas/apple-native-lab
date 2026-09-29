import LabCatalog
import SwiftUI

/// Menu bar commands for the essential actions, each with a keyboard shortcut. Window-specific
/// commands act on the frontmost main window and are disabled when none is in front.
struct LabCommands: Commands {
    let library: LabLibrary
    @FocusedValue(\.mainWindow) private var window

    var body: some Commands {
        SidebarCommands()

        CommandGroup(after: .sidebar) {
            Button(window?.showsInspector == true ? "Hide Receipt Inspector" : "Show Receipt Inspector") {
                window?.showsInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(window == nil)

            Divider()

            Button("Lab Collection") { window?.showCollection() }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(window == nil)
            Button("All Experiments") { window?.destination = .catalog(.all) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(window == nil)
            Button("First Release Journey") { window?.destination = .catalog(.milestone(.m1)) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(window == nil)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Search…") { window?.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(window == nil)
        }

        CommandMenu("Lab") {
            Button("Reset Demo…") { window?.isConfirmingReset = true }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(window == nil || !library.canAct)
            Button("Show Latest Receipt") {
                if let latest = library.latestReceipt { window?.inspect(latest) }
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(window == nil || library.latestReceipt == nil)
        }
    }
}
