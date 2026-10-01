import Foundation
import Testing
@testable import DurableSyncLedger

/// Fresh local directories and synthetic accounts; no CloudKit or OS reinstall is involved.
@Suite struct DurableSyncQualificationTests {
    @Test func anAlreadyCancelledImportWritesNothingAndCanBeRetried() async throws {
        let harness = try SyncHarness()
        let (source, _, _) = try await harness.ledger()
        try await source.edit(record: SyncFixtures.record, title: "Field note", note: "Manual exchange")
        let bytes = try await source.exportDocument().encoded()
        let (destination, _, _) = try await harness.ledger(device: SyncFixtures.device2, profile: DisabledSyncProfile())
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: LedgerError.cancelled) {
                try await destination.importDocument(bytes)
            }
        }
        await cancelled.value
        #expect(try await destination.exportDocument().envelopes.isEmpty)
        #expect(await destination.state(for: SyncFixtures.record) == .absent)
        try await destination.importDocument(bytes)
        try await destination.importDocument(bytes)
        #expect(await destination.state(for: SyncFixtures.record) == .live(title: "Field note", note: "Manual exchange"))
        #expect(try await destination.exportDocument().envelopes.count == 1)
    }

    @Test func wipingTheSameDeviceDirectoryRetainsTheRemoteTombstone() async throws {
        let harness = try SyncHarness()
        let (original, _, _) = try await harness.ledger()
        try await original.edit(record: SyncFixtures.record, title: "Field note", note: "Before deletion")
        let oldBytes = try await original.exportDocument().encoded()
        try await original.sync()
        try await original.delete(record: SyncFixtures.record)
        try await original.sync()

        let directory = harness.root
            .appending(path: SyncFixtures.accountA.rawValue.uuidString)
            .appending(path: SyncFixtures.device1.rawValue.uuidString)
            .appending(path: RecordScope.private.rawValue)
        try FileManager.default.removeItem(at: directory)
        let (reinstalled, _, _) = try await harness.ledger()
        #expect(await reinstalled.state(for: SyncFixtures.record) == .absent)
        try await reinstalled.sync()
        #expect(await reinstalled.state(for: SyncFixtures.record) == .deleted)
        try await reinstalled.importDocument(oldBytes)
        try await reinstalled.importDocument(oldBytes)
        #expect(await reinstalled.state(for: SyncFixtures.record) == .deleted)
        #expect(try await reinstalled.exportDocument().envelopes.count == 2)
    }

    @Test func aStaleChoiceCannotReplaceTheResolvedRecord() async throws {
        let harness = try SyncHarness()
        let (north, _, _) = try await harness.ledger()
        let (south, _, _) = try await harness.ledger(device: SyncFixtures.device2)
        try await north.edit(record: SyncFixtures.record, title: "Field note", note: "North count")
        try await south.edit(record: SyncFixtures.record, title: "Field note", note: "South count")
        try await north.sync()
        try await south.sync()
        try await north.sync()
        guard case .conflict(let conflict) = await north.state(for: SyncFixtures.record) else {
            Issue.record("Expected both offline edits")
            return
        }
        let choice = try #require(conflict.edits.first { $0.note == "North count" })
        try await north.resolve(record: SyncFixtures.record, choosing: choice.id)
        let before = try await north.exportDocument().encoded()
        await #expect(throws: LedgerError.self) {
            try await north.resolve(record: SyncFixtures.record, choosing: choice.id)
        }
        #expect(try await north.exportDocument().encoded() == before)
        try await north.sync()
        try await south.sync()
        #expect(await south.state(for: SyncFixtures.record) == .live(title: "Field note", note: "North count"))
    }
}
