import Foundation

/// A command the palette, the menus, and the menu-bar status can run.
///
/// Every command names the menu that also runs it. A gesture is listed separately, and each one
/// names that same kind of menu path, so nothing is reachable only by a gesture.
public enum DesktopCommand: String, Hashable, Sendable, CaseIterable {
    case showPalette
    case importSelectedText
    case importFile
    case openDocumentWindow
    case showStatus
    case resetFixtureState
    case importFixtureNote

    public var title: String {
        switch self {
        case .showPalette: "Command Palette…"
        case .importSelectedText: "Import Selected Text"
        case .importFile: "Import Desktop Note…"
        case .openDocumentWindow: "Open in New Window"
        case .showStatus: "Desktop Status"
        case .resetFixtureState: "Reset Fixture Notes"
        case .importFixtureNote: "Import Fixture Note"
        }
    }

    /// Where the command sits in the Mac menus. The palette shows the same path.
    public var menuPath: String {
        switch self {
        case .showPalette: "View > Command Palette…"
        case .importSelectedText: "Lab > Import Selected Text"
        case .importFile: "File > Import Desktop Note…"
        case .openDocumentWindow: "File > Open in New Window"
        case .showStatus: "View > Desktop Status"
        case .resetFixtureState: "Lab > Reset Fixture Notes"
        case .importFixtureNote: "Lab > Import Fixture Note"
        }
    }

    /// The keyboard path, written the way a menu shows it.
    public var shortcut: String {
        switch self {
        case .showPalette: "⌘K"
        case .importSelectedText: "⌃⌘T"
        case .importFile: "⌃⌘O"
        case .openDocumentWindow: "Return"
        case .showStatus: "⌥⌘9"
        case .resetFixtureState: "⌥⌘R"
        case .importFixtureNote: "⌥⌘N"
        }
    }

    public var entry: PaletteEntry {
        PaletteEntry(command: self, title: title, menuPath: menuPath, shortcut: shortcut)
    }
}

/// One row of the command palette: the command and the menu that does the same thing.
public struct PaletteEntry: Hashable, Sendable, Identifiable {
    public var id: DesktopCommand { command }
    public let command: DesktopCommand
    public let title: String
    public let menuPath: String
    public let shortcut: String

    public init(command: DesktopCommand, title: String, menuPath: String, shortcut: String) {
        self.command = command
        self.title = title
        self.menuPath = menuPath
        self.shortcut = shortcut
    }
}

extension DesktopCommand {
    /// Palette rows whose title or menu path contains `query`. An empty query is the whole list.
    public static func palette(matching query: String) -> [PaletteEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.map(\.entry).filter { entry in
            needle.isEmpty
                || entry.title.localizedStandardContains(needle)
                || entry.menuPath.localizedStandardContains(needle)
        }
    }
}

/// A gesture and the menu command that does the same thing without it.
public struct GestureAlternative: Hashable, Sendable {
    public let gesture: String
    public let menuPath: String
    public let shortcut: String

    public init(gesture: String, menuPath: String, shortcut: String) {
        self.gesture = gesture
        self.menuPath = menuPath
        self.shortcut = shortcut
    }
}

/// Gestures this experiment uses, each with a menu and a key. The menu bar is not one of them:
/// it repeats the status the window already shows.
public enum DesktopGestures {
    public static let all: [GestureAlternative] = [
        GestureAlternative(
            gesture: "Double-click a note",
            menuPath: DesktopCommand.openDocumentWindow.menuPath,
            shortcut: DesktopCommand.openDocumentWindow.shortcut
        ),
        GestureAlternative(
            gesture: "Click the menu-bar status item",
            menuPath: DesktopCommand.showStatus.menuPath,
            shortcut: DesktopCommand.showStatus.shortcut
        ),
    ]

    public static var everyGestureHasAMenuPath: Bool {
        all.allSatisfy { !$0.gesture.isEmpty && !$0.menuPath.isEmpty && !$0.shortcut.isEmpty }
    }
}

/// The menu-bar status. It counts notes and windows and never quotes a note's title or body,
/// so a private note cannot appear there.
public struct MenuBarStatus: Hashable, Sendable {
    public let noteCount: Int
    public let windowCount: Int
    public let summary: String

    public init(noteCount: Int, windowCount: Int, summary: String) {
        self.noteCount = noteCount
        self.windowCount = windowCount
        self.summary = summary
    }

    public static let empty = MenuBarStatus(noteCount: 0, windowCount: 0, summary: sentence(notes: 0, windows: 0))

    public static func sentence(notes: Int, windows: Int) -> String {
        let noteText = notes == 1 ? "1 note" : "\(notes) notes"
        let windowText = windows == 1 ? "1 window" : "\(windows) windows"
        return "\(noteText), \(windowText)"
    }
}
