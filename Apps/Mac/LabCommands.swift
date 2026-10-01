import LabCatalog
import SurfaceDeck
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
            Button("Action Atlas") { window?.destination = .actionAtlas }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(window == nil)
            Button(AccessSuperpowerExperiment.title) { window?.destination = .accessSuperpower }
                .keyboardShortcut("5", modifiers: .command)
                .disabled(window == nil)
            Button("Share Inbox") { window?.destination = .shareInbox }
                .keyboardShortcut("6", modifiers: .command)
                .disabled(window == nil)
            Button(SurfaceDeck.title) { window?.destination = .surfaceDeck }
                .keyboardShortcut("7", modifiers: .command)
                .disabled(window == nil)
            Button("Portable Objects") { window?.destination = .portableObjects }
                .keyboardShortcut("8", modifiers: .command)
                .disabled(window == nil)
            Button(HomeSceneExperiment.title) { window?.destination = .homeSceneSandbox }
                .keyboardShortcut("9", modifiers: .command)
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

            Divider()

            // The sample and receipt actions also live on buttons in the window. These give them a
            // keyboard path that does not depend on keyboard navigation reaching those buttons.
            archiveCommand
            undoCommand
        }
    }

    private var archiveCommand: some View {
        let sample = window?.selectedSample(in: library)
        return Button(sample?.isArchived == true ? "Restore Sample" : "Archive Sample") {
            guard let sample else { return }
            Task {
                let result = await library.setArchived(sample, !sample.isArchived)
                LabAnnouncement.outcome(of: result, in: library)?.post()
            }
        }
        .keyboardShortcut("a", modifiers: [.command, .control])
        .disabled(sample == nil || !library.canAct)
    }

    private var undoCommand: some View {
        let receipt = window?.shownReceipt(in: library)
        let presentation = receipt.map(ReceiptPresentation.init)
        let isOffered = presentation?.undo != nil && receipt.map { library.undone[$0.id] == nil } == true
        return Button(isOffered ? "Undo \(presentation?.operation ?? "")" : "Undo Receipt Change") {
            guard let receipt else { return }
            Task {
                let result = await library.undo(receipt)
                LabAnnouncement.outcome(of: result, in: library)?.post()
            }
        }
        .keyboardShortcut("z", modifiers: [.command, .option])
        .disabled(!isOffered || !library.canAct)
    }
}
