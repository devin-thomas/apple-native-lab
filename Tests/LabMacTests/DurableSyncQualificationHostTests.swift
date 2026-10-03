import DurableSyncLedger
import Foundation
import Testing
@testable import NativeLab

/// Calls the real host session on a fresh confined folder. No UI gestures or CloudKit.
@MainActor
@Suite struct DurableSyncQualificationHostTests {
    @Test func reopeningRetainsTheLogButDoesNotRebuildTheLiveView() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "LedgerReopen-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = DurableSyncSession(locateRoot: { root })
        await first.openIfNeeded()
        await first.save(title: "Field note", note: "Retained edit")
        let bytes = try #require(await first.exportSelected())
        let reopened = DurableSyncSession(locateRoot: { root })
        await reopened.openIfNeeded()
        #expect(await reopened.exportSelected() == bytes)
        withKnownIssue("LAB-017: applied markers outlive the host's in-memory store; reopening shows an absent live record") {
            #expect(reopened.selectedPane?.state == .live(title: "Field note", note: "Retained edit"))
        }
    }

    @Test func cleanReplayDeletionManualExchangeAndConfinedReset() async throws {
        let parent = FileManager.default.temporaryDirectory.appending(path: "LedgerQualification-\(UUID().uuidString)")
        let root = parent.appending(path: "demo")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let userFile = parent.appending(path: "user-import.json")
        let userBytes = Data("Original user-owned sentinel".utf8)
        try userBytes.write(to: userFile)
        let session = DurableSyncSession(locateRoot: { root })
        await session.openIfNeeded()
        #expect(session.panes.count == 2)
        #expect(session.panes.allSatisfy { $0.state == .absent })
        await session.save(title: "Field note", note: "North count")
        session.selected = SyncFixtures.device2
        await session.save(title: "Field note", note: "South count")
        await session.reconnect()
        guard case .conflict(let conflict) = session.selectedPane?.state else {
            Issue.record("Expected inspectable conflict")
            return
        }
        #expect(Set(conflict.edits.compactMap(\.note)) == ["North count", "South count"])
        let choice = try #require(conflict.edits.first { $0.note == "North count" })
        await session.choose(choice.id)
        await session.reconnect()
        #expect(session.panes.allSatisfy { $0.state == .live(title: "Field note", note: "North count") })
        await session.choose(choice.id)
        #expect(session.message?.contains("no conflict") == true)
        await session.setCloudEnabled(false)
        await session.reconnect()
        #expect(session.message?.contains("iCloud is off") == true)
        let bytes = try #require(await session.exportSelected())
        await session.reset()
        #expect(session.panes.allSatisfy { $0.state == .absent })
        await session.importSelected(bytes)
        await session.importSelected(bytes)
        #expect(await session.exportSelected() == bytes)
        #expect(session.selectedPane?.state == .live(title: "Field note", note: "North count"))
        await session.deleteSelected()
        #expect(session.selectedPane?.state == .deleted)
        let deleted = try #require(await session.exportSelected())
        await session.reset()
        await session.importSelected(deleted)
        #expect(session.selectedPane?.state == .deleted)
        #expect(try Data(contentsOf: userFile) == userBytes)
        #expect(DurableSyncExperiment.replayCaption.contains("This is not iCloud"))
    }
}
