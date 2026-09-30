import AppKit
import Foundation
import Testing
@testable import NativeLab

/// CORE-010: a keyboard user can reach and cancel every essential Mac operation. These check the
/// running app's own menus and the main window's Tab order; pressing the keys in the running app
/// is recorded separately (docs/BUILD_STATUS.md).
@MainActor
@Suite struct KeyboardAccessTests {
    @Test func tabFromSearchGoesToTheResultsThenOnInReadingOrder() {
        #expect(WindowPane.search.next(receiptsShowing: true) == .results)
        #expect(WindowPane.search.next(receiptsShowing: false) == .results)
        #expect(WindowPane.results.next(receiptsShowing: true) == .receipts)
        #expect(WindowPane.results.next(receiptsShowing: false) == .sidebar)
        #expect(WindowPane.receipts.next(receiptsShowing: true) == .sidebar)
        #expect(WindowPane.sidebar.next(receiptsShowing: true) == .search)
    }

    @Test(arguments: [true, false])
    func tabVisitsEveryStopOnceAndReturns(receiptsShowing: Bool) {
        var visited: [WindowPane] = []
        var pane = WindowPane.sidebar
        repeat {
            visited.append(pane)
            pane = pane.next(receiptsShowing: receiptsShowing)
        } while pane != .sidebar && visited.count < 10
        let expected: [WindowPane] = receiptsShowing ? [.sidebar, .search, .results, .receipts] : [.sidebar, .search, .results]
        #expect(visited == expected, "no stop repeats, so Tab cannot be trapped")
    }

    @Test func theReceiptListCountsAsAStopOnlyWhileItIsOnScreen() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "KeyboardAccessTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        let window = MainWindowState()
        window.showsInspector = true
        #expect(library.receipts.count == 1)
        #expect(!window.showsReceiptList(in: library), "one receipt shows no list")
        let amber = try #require(library.collections.first?.items.first)
        let archive = try #require(await library.setArchived(amber, true))
        #expect(window.showsReceiptList(in: library))
        window.showsInspector = false
        #expect(!window.showsReceiptList(in: library))

        // The menu commands act on what the window shows.
        #expect(window.selectedSample(in: library) == nil, "no sample outside the collection")
        window.destination = .collection
        window.itemID = amber.id
        #expect(window.selectedSample(in: library)?.isArchived == true)
        #expect(window.shownReceipt(in: library)?.id == archive.id, "the newest receipt when none is picked")
    }

    /// Every essential Mac operation has a menu item with a shortcut, read from the app's menus.
    @Test(arguments: [
        ("Search…", "f", NSEvent.ModifierFlags.command),
        ("Lab Collection", "1", [.command]),
        ("All Experiments", "2", [.command]),
        ("First Release Journey", "3", [.command]),
        ("Show Receipt Inspector", "i", [.command, .option]),
        ("Reset Demo…", "r", [.command, .shift]),
        ("Show Latest Receipt", "l", [.command, .option]),
        ("Archive Sample", "a", [.command, .control]),
        ("Undo Receipt Change", "z", [.command, .option]),
        ("Readiness", "0", [.command, .shift]),
    ] as [(String, String, NSEvent.ModifierFlags)])
    func essentialCommandsHaveShortcuts(title: String, key: String, modifiers: NSEvent.ModifierFlags) throws {
        let items = Self.menuItems(NSApp.mainMenu)
        // Titles that depend on state (a hidden inspector, no selected sample) may read either way.
        let alternates = ["Show Receipt Inspector": "Hide Receipt Inspector", "Archive Sample": "Restore Sample"]
        // The Window menu also lists the Readiness window by name, without a shortcut.
        let item = try #require(items.first { ($0.title == title || $0.title == alternates[title]) && !$0.keyEquivalent.isEmpty },
                                "no menu item \(title) with a shortcut among \(items.map(\.title))")
        #expect(item.keyEquivalent == key, "\(title)")
        #expect(item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == modifiers, "\(title)")
    }

    @Test func settingsHasTheStandardShortcut() throws {
        let item = try #require(Self.menuItems(NSApp.mainMenu).first { $0.keyEquivalent == "," })
        #expect(item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == .command)
    }

    /// Command shortcuts only: AppKit adds its own globe-key items (dictation, emoji) to Edit.
    /// A failure names each colliding item, its menu, and whether it is hidden or an alternate.
    @Test func noTwoCommandShortcutsCollide() {
        let items = Self.menuItems(NSApp.mainMenu)
            .filter { !$0.keyEquivalent.isEmpty && $0.keyEquivalentModifierMask.contains(.command) }
        let byShortcut = Dictionary(grouping: items) {
            "\($0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask).rawValue)-\($0.keyEquivalent.lowercased())"
        }
        let repeated = byShortcut.filter { $0.value.count > 1 }.mapValues { items in
            items.map { "\($0.title) in \($0.menu?.title ?? "no menu")\($0.isHidden ? ", hidden" : "")\($0.isAlternate ? ", alternate" : "")" }
        }
        #expect(repeated.isEmpty, "shortcuts used twice: \(repeated.sorted { $0.key < $1.key })")
    }

    /// Every item, after letting each menu fill itself in as it does when it opens.
    private static func menuItems(_ menu: NSMenu?) -> [NSMenuItem] {
        guard let menu else { return [] }
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.update()
        return menu.items.flatMap { [$0] + menuItems($0.submenu) }
    }
}
