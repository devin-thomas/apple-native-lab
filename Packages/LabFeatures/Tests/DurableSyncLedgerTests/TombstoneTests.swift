import Foundation
import LabDomain
import Testing
@testable import DurableSyncLedger

@Suite struct TombstoneReinstallTests {
    @Test func reinstallingDoesNotBringBackATombstonedRecord() async throws {
        let harness = try SyncHarness()
        let record = SyncFixtures.record
        let (device1, _, _) = try await harness.ledger()
        try await device1.edit(record: record, title: "Field note", note: "Counted")
        try await device1.sync()
        try await device1.delete(record: record)
        try await device1.sync()
        #expect(await device1.state(for: record) == .deleted)

        let (reinstalled, service, _) = try await harness.ledger(device: DeviceID())
        // A new device directory is a fresh install. The profile still holds the tombstone.
        // Use the same device identity so the folder matches... A reinstall of the same device
        // wipes the local directory. Build that by a second ledger on a new folder that pulls.
        _ = service
        try await reinstalled.sync()
        #expect(await reinstalled.state(for: record) == .deleted)
        let decision = await reinstalled.decision(for: record)
        #expect(decision?.explanation.contains("stays deleted") == true)
        #expect(decision?.explanation.contains("does not bring it back") == true)

        let stale = MutationID(rawValue: UUID(uuidString: "017F0002-0000-4000-8000-000000000002")!)
        let hostile = try MutationEnvelope(
            id: stale,
            record: record,
            account: SyncFixtures.accountA,
            device: SyncFixtures.device1,
            scope: .private,
            share: nil,
            vector: VersionVector(counters: [SyncFixtures.device1: 1]),
            kind: .upsert(title: "Field note", note: "Counted again")
        )
        try await reinstalled.plantUnappliedForTesting(hostile)
        try await reinstalled.open()
        #expect(await reinstalled.state(for: record) == .deleted)
    }

    @Test func aConcurrentEditDoesNotSilentlyResurrectADeletion() async throws {
        let harness = try SyncHarness()
        let record = SyncFixtures.record
        let (device1, _, _) = try await harness.ledger()
        let (device2, _, _) = try await harness.ledger(device: SyncFixtures.device2, label: SyncFixtures.device2Label)
        try await device1.edit(record: record, title: "Field note", note: "Counted")
        try await device1.sync()
        try await device2.sync()
        try await device1.delete(record: record)
        try await device2.edit(record: record, title: "Field note", note: "Late count")
        try await device1.sync()
        try await device2.sync()
        try await device1.sync()

        let state = await device1.state(for: record)
        guard case .conflict(let conflict) = state else {
            Issue.record("Expected the deletion and the late edit to stay inspectable")
            return
        }
        #expect(conflict.edits.contains { $0.kind.isTombstone })
        #expect(conflict.edits.contains { $0.note == "Late count" })
        #expect(await device1.state(for: record) != .live(title: "Field note", note: "Late count"))
    }
}
