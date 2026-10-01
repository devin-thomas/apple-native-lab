import Foundation
import LabDomain
@testable import LabStore
import Testing

/// LAB-032 Render That Survives: a job is stored in the same SQLite file and transaction as its
/// receipt, so a relaunch reads the truth a worker last committed. It keeps its namespace, a user
/// job is never deleted, and Reset Demo removes demo jobs only.
@Suite struct JobStoreTests {
    static let job = JobID(rawValue: uuid(60))

    private func perform(_ service: OperationService, _ operation: DomainOperation, id: RequestID = RequestID()) async throws -> ActionReceipt {
        try await service.perform(OperationRequest(id: id, operation: operation, actor: .appUI))
    }

    private func draft(_ id: JobID = JobStoreTests.job, total: Int? = 5, namespace: DataNamespace = .demo) throws -> JobDraft {
        try JobDraft(id: id, kind: .render, title: EntityTitle("Color bars"), total: total, namespace: namespace)
    }

    private func output() throws -> JobOutput {
        try JobOutput(name: "color-bars.mov", byteCount: 4_096, sha256: String(repeating: "ab", count: 32), summary: "2.0 s · 160×90")
    }

    @Test func aJobSurvivesReopeningTheFileInEveryPhase() async throws {
        let directory = try TemporaryDirectory()
        let startID = RequestID(rawValue: uuid(61))
        do {
            let store = try await SQLiteOperationStore(url: directory.storeURL)
            let service = OperationService(store: store)
            _ = try await perform(service, .startJob(draft: try draft()), id: startID)
            _ = try await perform(service, .updateJob(id: Self.job, expected: .r(1), transition: .checkpoint(completed: 2)))
            _ = try await perform(service, .updateJob(id: Self.job, expected: .r(2), transition: .interrupt(reason: .expired)))
        }
        do {
            let reopened = try await SQLiteOperationStore(url: directory.storeURL)
            let job = try #require(try await reopened.job(Self.job))
            let saved = try JobProgress(completed: 2, total: 5)
            #expect(job.phase == .interrupted(reason: .expired))
            #expect(job.progress == saved)
            #expect(job.revision == .r(3) && job.namespace == .demo && job.jobKind == .render)
            #expect(try await reopened.receipt(for: startID)?.summary == "Started render job “Color bars”.")

            let service = OperationService(store: reopened)
            _ = try await perform(service, .updateJob(id: Self.job, expected: .r(3), transition: .resume))
            _ = try await perform(service, .updateJob(id: Self.job, expected: .r(4), transition: .succeed(output: try output())))
        }
        let final = try await SQLiteOperationStore(url: directory.storeURL)
        let job = try #require(try await final.job(Self.job))
        let published = try output()
        let complete = try JobProgress(completed: 5, total: 5)
        #expect(job.phase == .succeeded(output: published))
        #expect(job.progress == complete)
        #expect(try await final.jobs().count == 1)
    }

    @Test func aJobWithAnUnknownTotalStoresNull() async throws {
        let directory = try TemporaryDirectory()
        let store = try await SQLiteOperationStore(url: directory.storeURL)
        _ = try await perform(OperationService(store: store), .startJob(draft: try draft(total: nil)))
        #expect(try await store.job(Self.job)?.progress.total == nil)
        let raw = try SQLiteDatabase(url: directory.storeURL)
        #expect(try DatabaseDump.rows(raw, "SELECT phase, total_units, detail FROM jobs") == [["running", "∅", #"{"running":{}}"#]])
    }

    @Test func anInterruptedCheckpointLeavesTheOldProgressAndNoReceipt() async throws {
        let directory = try TemporaryDirectory()
        let faults = FaultPlan()
        let store = try await SQLiteOperationStore.open(directory.storeURL, hook: faults.hook)
        let service = OperationService(store: store)
        _ = try await perform(service, .startJob(draft: try draft()))

        let requestID = RequestID(rawValue: uuid(62))
        faults.interrupt { $0 == .receiptRecorded }
        await #expect(throws: OperationError.storeFailure(.commitFailed)) {
            try await perform(service, .updateJob(id: Self.job, expected: .initial, transition: .checkpoint(completed: 1)), id: requestID)
        }
        #expect(try await store.job(Self.job)?.progress.completed == 0)
        #expect(try await store.job(Self.job)?.revision == .initial)
        #expect(try await store.receipt(for: requestID) == nil)
    }

    @Test func resetDemoRemovesDemoJobsAndNeverAUserJob() async throws {
        let directory = try TemporaryDirectory()
        let store = try await SQLiteOperationStore(url: directory.storeURL)
        let service = OperationService(store: store)
        let seed = try RepositoryFixtures.demoSeed()
        _ = try await perform(service, .resetDemo(seed: seed))
        let userJob = JobID(rawValue: uuid(63))
        _ = try await perform(service, .startJob(draft: try draft()))
        _ = try await perform(service, .startJob(draft: try draft(userJob, namespace: .user)))

        let reset = try await perform(service, .resetDemo(seed: seed))
        #expect(reset.removed == [EntityReference.job(Self.job)])
        #expect(reset.summary == "Reset the demo to its original 3 collections and 12 items: removed 1 job.")
        #expect(try await store.job(Self.job) == nil)
        #expect(try await store.job(userJob)?.namespace == .user)
    }

    @Test func version4FilesGainAnEmptyJobsTableAndKeepTheirRows() async throws {
        let directory = try TemporaryDirectory()
        do {
            let database = try SQLiteDatabase(url: directory.storeURL)
            try database.execute(StoreSchema.version1)
            try database.execute(StoreSchema.version2)
            try database.execute(StoreSchema.version3)
            try database.execute(StoreSchema.version4)
            try database.execute(
                "INSERT INTO collections (id, title, is_archived, revision, namespace) VALUES ('\(uuid(64).uuidString)', 'Kept', 0, 2, 'user')"
            )
            try database.execute("INSERT INTO sessions (id, is_running, revision) VALUES ('\(uuid(65).uuidString)', 1, 4)")
            try database.execute("PRAGMA user_version = 4; PRAGMA application_id = \(StoreSchema.applicationID)")
        }
        let before = try DatabaseDump(directory.storeURL)

        let store = try await SQLiteOperationStore(url: directory.storeURL)
        #expect(try await store.jobs().isEmpty)
        #expect(try await store.session(SessionID(rawValue: uuid(65)))?.revision == .r(4))
        #expect(try DatabaseDump(directory.storeURL) == before)
        let raw = try SQLiteDatabase(url: directory.storeURL)
        #expect(try raw.integer("PRAGMA user_version") == SQLiteOperationStore.schemaVersion)
        #expect(try raw.strings("SELECT name FROM pragma_table_info('jobs')") == [
            "id", "kind", "title", "phase", "detail", "completed_units", "total_units", "revision", "namespace", "extras",
        ])
    }

    @Test func theSchemaKeepsJobsInTheirNamespaceAndKindAndNeverDeletesAUserJob() throws {
        let directory = try TemporaryDirectory()
        let database = try SQLiteDatabase(url: directory.storeURL)
        for migration in StoreSchema.migrations { try database.execute(migration.sql) }
        let insert = """
            INSERT INTO jobs (id, kind, title, phase, detail, completed_units, total_units, revision, namespace)
            VALUES ('\(uuid(66).uuidString)', 'render', 'Kept', 'running', '{"running":{}}', 0, 3, 1, 'user')
            """
        try database.execute(insert)
        #expect(throws: SQLiteError.self) { try database.execute("UPDATE jobs SET namespace = 'demo'") }
        #expect(throws: SQLiteError.self) { try database.execute("UPDATE jobs SET kind = 'export'") }
        #expect(throws: SQLiteError.self) { try database.execute("DELETE FROM jobs") }
        // Progress past the total, and an unknown phase, are refused by the table itself.
        #expect(throws: SQLiteError.self) { try database.execute("UPDATE jobs SET completed_units = 4") }
        #expect(throws: SQLiteError.self) { try database.execute("UPDATE jobs SET phase = 'paused'") }
    }

    @Test func aRowWhosePhaseDisagreesWithItsDetailReadsAsCorrupt() async throws {
        let directory = try TemporaryDirectory()
        let store = try await SQLiteOperationStore(url: directory.storeURL)
        _ = try await perform(OperationService(store: store), .startJob(draft: try draft()))
        try await store.execute("UPDATE jobs SET phase = 'cancelled'")
        await #expect(throws: StoreError.corruptRecord) { try await store.job(Self.job) }
    }
}
