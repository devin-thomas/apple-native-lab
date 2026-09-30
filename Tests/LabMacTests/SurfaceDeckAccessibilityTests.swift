import AppKit
import Foundation
import LabDomain
import SurfaceDeck
import SwiftUI
import Testing
@testable import NativeLab

/// LAB-004-B step 5: the Surface Deck through the accessibility API, the automated rows of
/// docs/ACCESSIBILITY_REVIEW.md for this experiment. Each test renders the deck's real views in
/// the running Mac app, reads their accessibility tree, and presses controls through the
/// accessibility press action.
///
/// This is not a VoiceOver, Voice Control, or Full Keyboard Access pass, and the display
/// conditions are environment overrides, not the system settings. The system-drawn widget and
/// Controls are not here: the Mac has neither.
@MainActor
@Suite struct SurfaceDeckAccessibilityTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "SurfaceDeckAccessibilityTests-\(UUID().uuidString)")

    /// The deck's state card and toggle read the state and name what the toggle does, under every
    /// display condition, and the toggle works through the accessibility press action.
    @Test(arguments: DisplayConditions.all)
    func theStateAndItsToggleReadAndWorkUnderEveryCondition(_ conditions: DisplayConditions) async throws {
        let deck = try await QualifiedDeck.start(in: folder.appending(path: UUID().uuidString), withSurfaces: false)
        let hosted = AccessHostedView(
            List { SessionStateCard(model: deck.model); SessionToggleButton(model: deck.model) }.environment(deck.library),
            conditions: conditions
        )
        defer { hosted.close() }
        let before = try await hosted.elements()
        #expect(before.contains { $0.label == "Demo session, Paused" }, "\(conditions)\n\(before.dump)")
        let start = try #require(before.first { $0.role == "AXButton" && $0.label == "Start Session" }, "\(conditions)\n\(before.dump)")
        #expect(start.isEnabled)
        #expect(start.hint == "Changes the demo session. The receipt offers an undo.")

        #expect(try await hosted.press("Start Session"))
        let after = try await hosted.elements(until: { $0.contains { $0.role == "AXButton" && $0.label == "Pause Session" } })
        #expect(after.contains { $0.label == "Demo session, Running" }, "\(conditions)\n\(after.dump)")
        #expect(after.contains { $0.role == "AXButton" && $0.label == "Pause Session" && $0.isEnabled })
        #expect(after.contains { $0.spoken.contains("Started the demo session.") }, "the result is on screen in words")
        #expect(deck.library.latestReceipt?.receipt.admitted.adapter == .appUI)
    }

    /// Each preview is one element that says it is a preview drawn by the app, then reads the
    /// state. None speaks the private detail, even when details are shown on widgets.
    @Test func eachPreviewIsOneLabeledElementAndNeverSpeaksTheDetail() async throws {
        let deck = try await QualifiedDeck.start(in: folder, withSurfaces: false)
        _ = await deck.model.setRunning(true)
        deck.model.showsDetailsOnSurfaces = true
        #expect(deck.model.makeSnapshot().detail != nil)
        let hosted = AccessHostedView(SurfacePreviewGallery(model: deck.model).environment(deck.library))
        defer { hosted.close() }
        let elements = try await hosted.elements(until: { $0.filter { $0.label.hasPrefix("Preview of the") }.count == 5 })
        let previews = elements.filter { $0.label.hasPrefix("Preview of the") }
        #expect(previews.map(\.label) == [
            "Preview of the small widget, drawn by Native Lab",
            "Preview of the medium widget, drawn by Native Lab",
            "Preview of the lock screen, drawn by Native Lab",
            "Preview of the lock screen, locked, drawn by Native Lab",
            "Preview of the control, drawn by Native Lab",
        ], "\(elements.dump)")
        #expect(previews.allSatisfy { $0.value == "Demo session, Running." }, "\(elements.dump)")
        #expect(!elements.contains { $0.spoken.contains("Changed from") }, "no element speaks the detail\n\(elements.dump)")
    }

    /// Show Details on Widgets is a named switch, off by default, and pressing it writes the
    /// person's choice.
    @Test func showDetailsOnWidgetsIsANamedSwitchOffByDefault() async throws {
        let deck = try await QualifiedDeck.start(in: folder, withSurfaces: false)
        let hosted = AccessHostedView(List { SurfacesSection(model: deck.model) }.environment(deck.library))
        defer { hosted.close() }
        let elements = try await hosted.elements()
        let toggle = try #require(elements.first { $0.role == "AXCheckBox" && $0.label == "Show Details on Widgets" }, "\(elements.dump)")
        #expect(toggle.value == "0")
        #expect(elements.contains { $0.spoken.contains("This build has no widget or Control.") }, "\(elements.dump)")

        let selector = NSSelectorFromString("accessibilityPerformPress")
        try #require(toggle.object.responds(to: selector))
        _ = toggle.object.perform(selector)
        let after = try await hosted.elements(until: { $0.contains { $0.role == "AXCheckBox" && $0.value == "1" } })
        #expect(after.contains { $0.role == "AXCheckBox" && $0.value == "1" }, "\(after.dump)")
        #expect(deck.model.showsDetailsOnSurfaces)
        #expect(deck.defaults.bool(forKey: SurfaceDeckModel.detailsKey))
    }

    /// After a change, the receipt row reads its status, and the Undo button names what it undoes
    /// and works through the accessibility press action.
    @Test func theReceiptAndItsUndoAreReachableByName() async throws {
        let deck = try await QualifiedDeck.start(in: folder, withSurfaces: false)
        _ = await deck.model.setRunning(true)
        let hosted = AccessHostedView(List { SessionReceiptsSection(model: deck.model) { _ in } }.environment(deck.library))
        defer { hosted.close() }
        let elements = try await hosted.elements()
        let row = try #require(elements.first { $0.role == "AXButton" && $0.label.contains("Status: Committed") }, "\(elements.dump)")
        #expect(row.label.hasPrefix("Start Session"), "\(row.label)")
        #expect(row.hint == "Shows the receipt in the inspector.")

        #expect(try await hosted.press("Undo Start Session"), "\(elements.dump)")
        _ = try await hosted.elements(until: { _ in deck.library.latestReceipt?.receipt.summary == "Paused the demo session." })
        await deck.model.refresh()
        #expect(deck.model.state == SessionState(isRunning: false, revision: 2))
        #expect(deck.library.latestReceipt?.receipt.admitted.adapter == .appUI)
    }

    /// The deck has a menu command with a shortcut, so it is reachable without keyboard navigation.
    @Test func theDeckHasAMenuCommandWithCommand7() throws {
        func items(_ menu: NSMenu?) -> [NSMenuItem] {
            guard let menu else { return [] }
            menu.delegate?.menuNeedsUpdate?(menu)
            menu.update()
            return menu.items.flatMap { [$0] + items($0.submenu) }
        }
        let item = try #require(items(NSApp.mainMenu).first { $0.title == SurfaceDeck.title && !$0.keyEquivalent.isEmpty })
        #expect(item.keyEquivalent == "7")
        #expect(item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == .command)
    }
}
