import AppKit
import Foundation
import LabDomain
import SwiftUI
import TabletopReality
import Testing
@testable import NativeLab

/// LAB-023-B step 5: Tabletop Reality through the accessibility API, the automated rows of
/// docs/ACCESSIBILITY_REVIEW.md for this experiment. Each test renders the experiment's real Mac
/// views in the running app, reads their accessibility tree, and acts through the accessibility
/// press and custom actions, as VoiceOver and Voice Control do.
///
/// This is not a VoiceOver, Voice Control, or Full Keyboard Access pass, and the display
/// conditions are environment overrides, not the system settings.
@MainActor
@Suite(.serialized) struct TabletopAccessibilityTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "TabletopAccessibilityTests-\(UUID().uuidString)")

    private func started() async throws -> (LabLibrary, TabletopSession) {
        let directory = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        let session = TabletopSession()
        await session.start(in: library)
        session.setOutStarter(in: library)
        try await TabletopHostEvidenceTests.waitUntil { !session.isRunningList }
        try #require(session.anchors.count == 4)
        return (library, session)
    }

    /// The object list names the table and every object once, with its place in words, and each
    /// object's row carries Select, the four moves, both turns, and Remove. A custom action runs
    /// the same operation a button does, with a receipt.
    @Test func theListNamesEveryObjectAndItsActionsChangeTheTable() async throws {
        let (library, session) = try await started()
        let window = MainWindowState()
        let hosted = AccessHostedView(TabletopListColumn(window: window, session: session).environment(library))
        defer { hosted.close() }
        let elements = try await hosted.elements(until: { $0.contains { $0.spoken.contains("Windmill") && !$0.actions.isEmpty } })

        for entry in session.entries {
            let rows = elements.filter { $0.spoken.contains(entry.label) && $0.spoken.contains(entry.value) }
            #expect(!rows.isEmpty, "\(entry.label) is read with its place\n\(elements.dump)")
        }
        let actions = ["Select", "Move Left", "Move Right", "Move Toward You", "Move Away from You", "Turn Left", "Turn Right", "Remove"]
        // AppKit lists a row's custom actions last to first; the set is what VoiceOver offers.
        let objectRows = elements.filter { Set($0.actions) == Set(actions) && $0.actions.count == actions.count }
        #expect(objectRows.count == 4, "one row with every action per object\n\(elements.dump)")
        #expect(!elements.contains { $0.spoken.contains("Oak table") && !$0.actions.isEmpty }, "the table's row has no object actions")

        let windmill = try #require(objectRows.first { $0.spoken.contains("Windmill") })
        let before = library.receipts.count
        #expect(windmill.perform(action: "Move Right"))
        try await TabletopHostEvidenceTests.waitUntil { library.receipts.count == before + 1 }
        #expect(library.latestReceipt?.receipt.summary == "Moved “Windmill”.")
        #expect(library.latestReceipt?.receipt.admitted.adapter == .appUI)
        let moved = try #require(session.anchors.first { $0.title.value == "Windmill" })
        #expect(moved.pose.x == -220)
        let after = try await hosted.elements(until: { $0.contains { $0.spoken.contains("22 cm left of center") } })
        #expect(after.contains { $0.spoken.contains("Windmill") && $0.spoken.contains("22 cm left of center") }, "\(after.dump)")
    }

    /// Under every display condition, placing and the selection's controls are named buttons. While
    /// tracking is lost they are disabled and a sentence says why, and Remove stays available.
    @Test(arguments: DisplayConditions.all)
    func trackingLossDisablesPrecisionControlsAndSaysWhy(_ conditions: DisplayConditions) async throws {
        let (library, session) = try await started()
        let windmill = try #require(session.anchors.first { $0.title.value == "Windmill" })
        session.selectedAnchorID = windmill.id
        let hosted = AccessHostedView(Form {
            TrackingStatusSection(session: session)
            PlacementControls(session: session)
            SelectionControls(session: session)
        }.environment(library), conditions: conditions)
        defer { hosted.close() }

        let ready = try await hosted.elements(until: { $0.contains { $0.role == "AXButton" && $0.label == "Place on Table" } })
        for name in ["Place on Table", "Set Out Starter Scene", "Move Left", "Move Right", "Move Toward You", "Move Away from You",
                     "Turn Left", "Turn Right", "Remove Windmill"] {
            #expect(ready.contains { $0.role == "AXButton" && $0.label == name && $0.isEnabled }, "\(name) under \(conditions)\n\(ready.dump)")
        }

        session.liveTrackingChanged(.limited(.excessiveMotion))
        let lost = try await hosted.elements(until: {
            $0.contains { $0.role == "AXButton" && $0.label == "Place on Table" && !$0.isEnabled }
        })
        for name in ["Place on Table", "Set Out Starter Scene", "Move Left", "Move Right", "Turn Left", "Turn Right"] {
            #expect(lost.contains { $0.role == "AXButton" && $0.label == name && !$0.isEnabled }, "\(name) disabled under \(conditions)\n\(lost.dump)")
        }
        #expect(lost.contains { $0.role == "AXButton" && $0.label == "Remove Windmill" && $0.isEnabled }, "\(lost.dump)")
        #expect(lost.contains { $0.spoken.contains("Moving too fast: placing, moving, and turning wait until tracking is normal.") }, "\(lost.dump)")
        #expect(lost.contains { $0.spoken.contains("Slow down. Placing and moving are paused until tracking is normal again.") }, "\(lost.dump)")
        session.liveEnded()
    }

    /// The replay says it is a recording wherever it shows, in words a screen reader reads.
    @Test func theReplayIsReadAsARecording() async throws {
        let (library, session) = try await started()
        let hosted = AccessHostedView(Form {
            TrackingStatusSection(session: session)
            TableActions(session: session)
        }.environment(library))
        defer { hosted.close() }
        #expect(try await hosted.press("Replay Tracking Loss"))
        let playing = try await hosted.elements(until: { $0.contains { $0.role == "AXButton" && $0.label == "Stop Replay" } })
        #expect(playing.contains { $0.spoken.contains("A recorded tracking sequence, not a camera.") }, "\(playing.dump)")
        #expect(playing.contains { $0.spoken.hasPrefix("Replay: ") }, "the tracking value says Replay\n\(playing.dump)")
        #expect(try await hosted.press("Stop Replay"))
        _ = try await hosted.elements(until: { _ in session.trackingSource == .virtualScene })
        #expect(session.tracking == .virtualScene)
    }

    /// The experiment has a View menu command with ⌃⌘4, so it is reachable without the sidebar.
    @Test func theExperimentHasAMenuCommandWithControlCommand4() throws {
        func items(_ menu: NSMenu?) -> [NSMenuItem] {
            guard let menu else { return [] }
            menu.delegate?.menuNeedsUpdate?(menu)
            menu.update()
            return menu.items.flatMap { [$0] + items($0.submenu) }
        }
        let item = try #require(items(NSApp.mainMenu).first { $0.title == TabletopExperiment.title && !$0.keyEquivalent.isEmpty })
        #expect(item.keyEquivalent == "4")
        #expect(item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == [.command, .control])
    }
}
