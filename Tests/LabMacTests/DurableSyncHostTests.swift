import DurableSyncLedger
import Foundation
import Testing
@testable import NativeLab

/// LAB-017 in the sandboxed Mac host: the sidebar destination and a two-device fixture session
/// under a temporary folder, never the app's Application Support ledger.
@MainActor
@Suite struct DurableSyncHostTests {
    @Test func theLedgerIsASidebarDestination() {
        #expect(SidebarDestination(storageKey: SidebarDestination.durableSync.storageKey) == .durableSync)
        #expect(SidebarDestination.durableSync.title == "Durable Sync Ledger")
        #expect(SidebarDestination.durableSync.title == DurableSyncExperiment.title)
    }

    @Test func twoDevicesKeepApartEditsUntilAChoice() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "DurableSyncHostTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = DurableSyncSession(locateRoot: { folder })
        await session.openIfNeeded()
        #expect(session.panes.count == 2)
        #expect(session.message == nil)

        session.selected = SyncFixtures.device1
        await session.save(title: "Field note", note: "North count")
        session.selected = SyncFixtures.device2
        await session.save(title: "Field note", note: "South count")
        await session.reconnect()

        let conflicted = try #require(session.panes.first { $0.id == SyncFixtures.device1 })
        guard case .conflict(let conflict) = conflicted.state else {
            Issue.record("Expected edits made apart, got \(conflicted.state)")
            return
        }
        #expect(Set(conflict.edits.compactMap(\.note)) == ["North count", "South count"])
        #expect(conflict.explanation.contains("Nothing was overwritten"))

        let north = try #require(conflict.edits.first { $0.note == "North count" })
        session.selected = SyncFixtures.device1
        await session.choose(north.id)
        await session.reconnect()

        #expect(session.panes.allSatisfy {
            if case .live(_, "North count") = $0.state { true } else { false }
        })
        #expect(session.panes.first?.explanation.contains("You chose") == true)
    }

    @Test func disabledProfileStillExportsAndImports() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "DurableSyncHostExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = DurableSyncSession(locateRoot: { folder })
        await session.openIfNeeded()
        await session.save(title: "Field note", note: "Local only")
        await session.setCloudEnabled(false)
        await session.reconnect()
        #expect(session.message?.contains("iCloud is off") == true)

        let bytes = try #require(await session.exportSelected())
        await session.reset()
        #expect(session.panes.allSatisfy {
            if case .absent = $0.state { true } else { false }
        })
        await session.importSelected(bytes)
        #expect(session.selectedPane?.state == .live(title: "Field note", note: "Local only"))
    }
}
