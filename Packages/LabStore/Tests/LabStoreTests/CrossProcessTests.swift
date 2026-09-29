#if os(macOS)
import Foundation
import LabDomain
@testable import LabStore
import Testing

private let sqliteTool = "/usr/bin/sqlite3"

/// The store's checks and writes hold SQLite's write lock against other processes, which an App
/// Group store shared with extensions will need. The other process here is the system `sqlite3`
/// tool writing the same file; nothing waits on a clock to decide an outcome.
@Suite(.enabled(if: FileManager.default.isExecutableFile(atPath: sqliteTool), "needs /usr/bin/sqlite3"))
struct CrossProcessTests {
    static let tool = sqliteTool

    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    /// Runs one SQL script in a separate `sqlite3` process that gives up on a lock after 200 ms.
    static func otherProcess(_ database: URL, _ sql: String) -> Result {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = ["-bail", "-cmd", ".timeout 200", database.path(percentEncoded: false), sql]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "\(error)")
        }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return Result(status: process.terminationStatus, output: output)
    }

    static func seeded() async throws -> (TemporaryDirectory, FaultPlan, SQLiteOperationStore, OperationService, DemoSeed) {
        let directory = try TemporaryDirectory()
        let faults = FaultPlan()
        let store = try await SQLiteOperationStore.open(directory.storeURL, hook: faults.hook)
        let service = OperationService(store: store)
        let seed = try RepositoryFixtures.demoSeed()
        _ = try await service.perform(OperationRequest(id: RequestID(), operation: .resetDemo(seed: seed), actor: .appUI))
        return (directory, faults, store, service, seed)
    }

    @Test func anotherProcessCannotWriteBetweenTheChecksAndTheWrites() async throws {
        let (directory, faults, store, service, seed) = try await Self.seeded()
        let amber = seed.items[0].id
        let blocked = Locked<Result?>(nil)
        let otherWrite = "UPDATE items SET note = 'From another process', revision = revision + 1 WHERE id = '\(amber)'"
        faults.observe { point in
            // The receipt and preconditions are checked; this commit has written nothing yet.
            if point == .preconditionsChecked, blocked.value == nil {
                blocked.set(Self.otherProcess(directory.storeURL, otherWrite))
            }
        }

        let receipt = try await service.perform(OperationRequest(
            id: RequestID(), operation: .updateItem(id: amber, expected: .initial, changes: ItemChanges(title: "From this process")),
            actor: .appUI
        ))
        faults.observe(nil)

        let refused = try #require(blocked.value)
        #expect(refused.status != 0)
        #expect(refused.output.contains("database is locked"))
        #expect(receipt.status == .committed)
        #expect(try await store.item(amber)?.revision == .r(2))

        // Once the commit is done, the other process can write, and this store sees it.
        let later = Self.otherProcess(directory.storeURL, otherWrite)
        #expect(later.status == 0, "\(later.output)")
        let current = try #require(try await store.item(amber))
        #expect(current.note == "From another process" && current.revision == .r(3))
    }

    @Test func aCommitFromAnotherProcessBeforeTheLockMakesAStaleWriteAConflict() async throws {
        let (directory, _, store, _, seed) = try await Self.seeded()
        let wrapped = ContractStore(store)
        let service = OperationService(store: wrapped)
        let amber = seed.items[0].id
        let otherWrite = "UPDATE items SET title = 'From another process', revision = revision + 1 WHERE id = '\(amber)'"
        let result = Locked<Result?>(nil)

        // After this service planned against revision 1, and before it takes the write lock.
        await wrapped.runBeforeNextCommit {
            result.set(Self.otherProcess(directory.storeURL, otherWrite))
        }
        let receipt = try await service.perform(OperationRequest(
            id: RequestID(), operation: .updateItem(id: amber, expected: .initial, changes: ItemChanges(title: "From this process")),
            actor: .appUI
        ))

        #expect(result.value?.status == 0)
        #expect(receipt.conflict?.expected == .initial)
        #expect(receipt.conflict?.current == .r(2))
        #expect(try await store.item(amber)?.title == "From another process")
    }
}
#endif
