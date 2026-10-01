import Foundation
import LabDomain
import Testing
@testable import DurableSyncLedger

@Suite struct LedgerOperationTests {
    private static let record = SyncFixtures.record

    @Test func aDeletionWithoutAGrantCommitsNothing() async throws {
        let harness = try SyncHarness()
        let (ledger, service, _) = try await harness.ledger(grantMode: .requireExisting)
        let created = MutationID(rawValue: UUID(uuidString: "017F0010-0000-4000-8000-000000000010")!)
        try await ledger.edit(record: Self.record, title: "Field note", note: "Keep", mutation: created)
        let createReceipt = try await service.findReceipt(for: created.requestID, as: harnessActor)
        #expect(createReceipt?.status == .committed)
        #expect(createReceipt?.summary.isEmpty == false)

        let deletion = MutationID(rawValue: UUID(uuidString: "017F0011-0000-4000-8000-000000000011")!)
        await #expect(throws: LedgerError.unauthorized) {
            try await ledger.delete(record: Self.record, mutation: deletion)
        }
        #expect(try await service.findReceipt(for: deletion.requestID, as: harnessActor) == nil)
        #expect(await ledger.state(for: Self.record) == .live(title: "Field note", note: "Keep"))
        let document = try await ledger.exportDocument()
        #expect(document.envelopes.contains { $0.id == deletion } == false)
    }

    @Test func aModelToolCannotCommit() async throws {
        let harness = try SyncHarness()
        let tool = ActorScope(adapter: .modelTool, grants: Set(Permission.allCases))
        let (ledger, service, _) = try await harness.ledger(grantMode: .requireExisting, actor: tool)
        let mutation = MutationID()
        await #expect(throws: LedgerError.unauthorized) {
            try await ledger.edit(record: Self.record, title: "Field note", note: "From a model", mutation: mutation)
        }
        #expect(try await service.findReceipt(for: mutation.requestID, as: tool) == nil)
        #expect(await ledger.state(for: Self.record) == .absent)
    }

    @Test func cancellingTheCommitLeavesTheLedgerUnchanged() async throws {
        let harness = try SyncHarness()
        let directory = harness.root.appending(path: "cancel", directoryHint: .isDirectory)
        let ledger = try SyncLedger(
            directory: directory,
            account: SyncFixtures.accountA,
            device: SyncFixtures.device1,
            deviceLabel: SyncFixtures.device1Label,
            scope: .private,
            share: nil,
            profile: DisabledSyncProfile(),
            backend: CancellingBackend()
        )
        await #expect(throws: LedgerError.cancelled) {
            try await ledger.edit(record: Self.record, title: "Field note", note: "Cancelled")
        }
        #expect(await ledger.state(for: Self.record) == .absent)
        #expect(try await ledger.exportDocument().envelopes.isEmpty)
    }

    @Test func invalidInputIsRefused() async throws {
        let harness = try SyncHarness()
        let (ledger, _, _) = try await harness.ledger()
        await #expect(throws: LedgerError.self) {
            try await ledger.edit(record: Self.record, title: "   ", note: "x")
        }
        await #expect(throws: LedgerError.self) {
            try await ledger.edit(record: Self.record, title: "Field note", note: String(repeating: "n", count: 2_001))
        }
        #expect(await ledger.state(for: Self.record) == .absent)

        let folder = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/LAB-017", directoryHint: .isDirectory)
        let publicScope = try Data(contentsOf: folder.appending(path: "public-scope.json"))
        await #expect(throws: LedgerError.self) {
            try await ledger.importDocument(publicScope)
        }
        let newer = try Data(contentsOf: folder.appending(path: "newer-schema.json"))
        await #expect(throws: LedgerError.self) {
            try await ledger.importDocument(newer)
        }
        #expect(CloudKitSurface.linkedInCoreLocal == false)
        #expect(CloudKitSurface.publicDatabaseIsForbidden)
        #expect(CloudKitSurface.automaticSyncStaysOff)
        #expect(CloudKitSurface.entitlementInCoreLocal == false)
        #expect(RecordScope.allCases == [.private, .shared])
    }

    @Test func aCrashBetweenTheLogAndTheCommitReplaysOnce() async throws {
        let harness = try SyncHarness()
        let (ledger, service, _) = try await harness.ledger(grantMode: .requireExisting)
        let mutation = MutationID(rawValue: UUID(uuidString: "017F0020-0000-4000-8000-000000000020")!)
        let envelope = try MutationEnvelope(
            id: mutation,
            record: Self.record,
            account: SyncFixtures.accountA,
            device: SyncFixtures.device1,
            scope: .private,
            share: nil,
            vector: VersionVector(counters: [SyncFixtures.device1: 1]),
            kind: .upsert(title: "Field note", note: "Recovered")
        )
        try await ledger.plantUnappliedForTesting(envelope)
        #expect(await ledger.state(for: Self.record) == .absent)
        try await ledger.open()
        #expect(await ledger.state(for: Self.record) == .live(title: "Field note", note: "Recovered"))
        let first = try await service.findReceipt(for: mutation.requestID, as: harnessActor)
        try await ledger.open()
        let second = try await service.findReceipt(for: mutation.requestID, as: harnessActor)
        #expect(first?.operationID == second?.operationID)
        #expect(first?.status == .committed)
    }

    @Test func importingTheSameDocumentDoesNotDuplicateTheRecord() async throws {
        let harness = try SyncHarness()
        let (source, _, _) = try await harness.ledger()
        try await source.edit(record: Self.record, title: "Field note", note: "Once")
        let bytes = try await source.exportDocument().encoded()
        let (destination, _, _) = try await harness.ledger(device: SyncFixtures.device2, label: SyncFixtures.device2Label, profile: DisabledSyncProfile())
        try await destination.importDocument(bytes)
        try await destination.importDocument(bytes)
        #expect(await destination.state(for: Self.record) == .live(title: "Field note", note: "Once"))
        #expect(try await destination.exportDocument().envelopes.count == 1)
    }
}

private let harnessActor = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

private struct CancellingBackend: LedgerBackend {
    func collection(_ id: CollectionID) async throws(LedgerError) -> LabCollection? { nil }
    func item(_ id: ItemID) async throws(LedgerError) -> LabItem? { nil }
    func perform(_ operation: DomainOperation, id: RequestID) async throws(LedgerError) -> ActionReceipt {
        throw .cancelled
    }
}
