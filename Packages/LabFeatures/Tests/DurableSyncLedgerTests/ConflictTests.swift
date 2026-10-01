import Foundation
import LabDomain
import Testing
@testable import DurableSyncLedger

@Suite struct ConflictAndCausalTests {
    @Test func editsMadeApartStayInspectableUntilSomeoneChooses() async throws {
        let harness = try SyncHarness()
        let (device1, _, _) = try await harness.ledger(device: SyncFixtures.device1, label: SyncFixtures.device1Label)
        let (device2, _, _) = try await harness.ledger(device: SyncFixtures.device2, label: SyncFixtures.device2Label)
        let record = SyncFixtures.record

        try await device1.edit(record: record, title: "Field note", note: "Shared start")
        try await device1.sync()
        try await device2.sync()
        try await device1.edit(record: record, title: "Field note", note: "North count")
        try await device2.edit(record: record, title: "Field note", note: "South count")
        try await device1.sync()
        try await device2.sync()
        try await device1.sync()

        let state = await device1.state(for: record)
        guard case .conflict(let conflict) = state else {
            Issue.record("Expected a conflict, got \(state)")
            return
        }
        let notes = Set(conflict.edits.compactMap(\.note))
        #expect(notes == ["North count", "South count"])
        #expect(conflict.explanation.contains("made apart"))
        #expect(conflict.explanation.contains("Nothing was overwritten"))
        #expect(conflict.storedNote == "North count")

        let north = try #require(conflict.edits.first { $0.note == "North count" })
        let decision = try await device1.resolve(record: record, choosing: north.id)
        #expect(decision.explanation.contains("You chose the edit from Device 1"))
        #expect(decision.explanation.contains("North count"))
        let resolved = await device1.state(for: record)
        #expect(resolved == .live(title: "Field note", note: "North count"))

        try await device1.sync()
        try await device2.sync()
        #expect(await device2.state(for: record) == .live(title: "Field note", note: "North count"))
        #expect(await device2.decision(for: record)?.receiptSummary != nil)
    }

    @Test func anEditThatSawTheOtherHappensAfterIt() async throws {
        let harness = try SyncHarness()
        let (device1, _, _) = try await harness.ledger()
        let (device2, _, _) = try await harness.ledger(device: SyncFixtures.device2, label: SyncFixtures.device2Label)
        let record = SyncFixtures.record
        try await device1.edit(record: record, title: "Field note", note: "First")
        try await device1.sync()
        try await device2.sync()
        try await device2.edit(record: record, title: "Field note", note: "Second")
        try await device2.sync()
        try await device1.sync()

        let decision = await device1.decision(for: record)
        #expect(decision?.explanation.contains("happened after") == true)
        #expect(await device1.state(for: record) == .live(title: "Field note", note: "Second"))
        if case .conflict = await device1.state(for: record) {
            Issue.record("A causal edit was treated as a conflict")
        }
    }
}
