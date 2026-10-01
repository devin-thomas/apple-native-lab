import Foundation
import LabDomain
@testable import LabStore
import Testing

/// LAB-043 Respectful Attention: lab alerts live in the same SQLite file and transaction as their
/// receipts, survive reopening, and Reset Demo removes only those demo rows.
@Suite struct AttentionStoreTests {
    static let reminder = AttentionID(rawValue: uuid(50))
    static let alarm = AttentionID(rawValue: uuid(51))

    private func draft(
        _ id: AttentionID,
        channel: AttentionChannel = .reminder,
        reason: String,
        hour: Int
    ) throws -> AttentionDraft {
        try AttentionDraft(
            id: id,
            channel: channel,
            reason: AttentionReason(reason),
            moment: CivilMoment(
                year: 2026, month: 10, day: 1, hour: hour, minute: 0, timeZoneIdentifier: "America/Chicago"
            ),
            consent: .explicit
        )
    }

    private func perform(_ service: OperationService, _ operation: DomainOperation) async throws -> ActionReceipt {
        try await service.perform(OperationRequest(id: RequestID(), operation: operation, actor: .appUI))
    }

    @Test func anAlertAndItsReceiptSurviveReopeningTheFile() async throws {
        let directory = try TemporaryDirectory()
        let requestID = RequestID(rawValue: uuid(52))
        do {
            let store = try await SQLiteOperationStore(url: directory.storeURL)
            let service = OperationService(store: store)
            let scheduled = try await service.perform(OperationRequest(
                id: requestID,
                operation: .scheduleAttention(expected: nil, draft: draft(Self.reminder, reason: "Review the sample notebook", hour: 9)),
                actor: .appUI
            ))
            #expect(scheduled.changes.map(\.newRevision) == [.initial])
            _ = try await perform(
                service,
                .scheduleAttention(expected: nil, draft: draft(Self.alarm, channel: .alarm, reason: "Stand and stretch", hour: 15))
            )
        }
        let reopened = try await SQLiteOperationStore(url: directory.storeURL)
        let reminder = try #require(try await reopened.attention(Self.reminder))
        #expect(reminder.channel == .reminder)
        #expect(reminder.moment.timeZoneIdentifier == "America/Chicago")
        #expect(reminder.moment.hour == 9)
        #expect(try await reopened.attentions().map(\.id).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
            == [Self.reminder, Self.alarm].sorted { $0.rawValue.uuidString < $1.rawValue.uuidString })
        #expect(try await reopened.receipt(for: requestID)?.summary.contains("Review the sample notebook") == true)
    }

    @Test func cancelRemovesOnlyNamedAlertsAndResetRemovesTheRest() async throws {
        let directory = try TemporaryDirectory()
        let store = try await SQLiteOperationStore(url: directory.storeURL)
        let service = OperationService(store: store)
        let seed = try RepositoryFixtures.demoSeed()
        _ = try await perform(service, .resetDemo(seed: seed))
        let mine = CollectionID(rawValue: uuid(53))
        _ = try await perform(service, .createCollection(draft: CollectionDraft(id: mine, title: "Mine")))
        _ = try await perform(service, .scheduleAttention(expected: nil, draft: try draft(Self.reminder, reason: "Review the sample notebook", hour: 9)))
        _ = try await perform(service, .scheduleAttention(expected: nil, draft: try draft(Self.alarm, channel: .alarm, reason: "Stand and stretch", hour: 15)))

        let cancelled = try await perform(service, .cancelLabAlerts(pins: [AttentionPin(id: Self.alarm, expected: .initial)]))
        #expect(cancelled.removed == [.attention(Self.alarm)])
        #expect(try await store.attentions().map(\.id) == [Self.reminder])
        #expect(try await store.collection(mine)?.namespace == .user)

        let reset = try await perform(service, .resetDemo(seed: seed))
        #expect(reset.removed.contains(.attention(Self.reminder)))
        #expect(try await store.attentions().isEmpty)
        #expect(try await store.collection(mine)?.namespace == .user)
    }

    @Test func aVersion3FileGainsAnEmptyAttentionsTableAndKeepsItsRows() async throws {
        let directory = try TemporaryDirectory()
        do {
            let database = try SQLiteDatabase(url: directory.storeURL)
            try database.execute(StoreSchema.version1)
            try database.execute(StoreSchema.version2)
            try database.execute(StoreSchema.version3)
            try database.execute(
                "INSERT INTO collections (id, title, is_archived, revision, namespace) VALUES ('\(uuid(54).uuidString)', 'Kept', 0, 3, 'user')"
            )
            try database.execute("PRAGMA user_version = 3; PRAGMA application_id = \(StoreSchema.applicationID)")
        }
        let before = try DatabaseDump(directory.storeURL)

        let store = try await SQLiteOperationStore(url: directory.storeURL)
        #expect(try await store.attentions().isEmpty)
        #expect(try DatabaseDump(directory.storeURL) == before)
        let raw = try SQLiteDatabase(url: directory.storeURL)
        #expect(try raw.integer("PRAGMA user_version") == SQLiteOperationStore.schemaVersion)
        #expect(try raw.strings("SELECT name FROM pragma_table_info('attentions')") == [
            "id", "channel", "reason", "year", "month", "day", "hour", "minute", "time_zone", "revision", "namespace", "extras",
        ])
    }

    @Test func theSchemaKeepsAttentionsInTheDemoNamespace() throws {
        let directory = try TemporaryDirectory()
        let database = try SQLiteDatabase(url: directory.storeURL)
        for migration in StoreSchema.migrations { try database.execute(migration.sql) }
        #expect(throws: SQLiteError.self) {
            try database.execute(
                """
                INSERT INTO attentions (id, channel, reason, year, month, day, hour, minute, time_zone, revision, namespace)
                VALUES ('\(uuid(55).uuidString)', 'reminder', 'Outside', 2026, 10, 1, 9, 0, 'America/Chicago', 1, 'user')
                """
            )
        }
    }
}
