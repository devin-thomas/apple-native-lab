import Foundation
import LabDomain
@testable import LabStore
import Synchronization
import Testing

// Fault injection and raw file access are internal to LabStore, so this file imports it
// @testable. Everything else in the tests goes through the public API.

extension EntityTitle: @retroactive ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        do { try self.init(value) } catch { fatalError("Invalid test title \(value): \(error)") }
    }
}

extension ItemNote: @retroactive ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        do { try self.init(value) } catch { fatalError("Invalid test note: \(error)") }
    }
}

extension ActorScope {
    static func granted(_ adapter: AdapterKind) -> ActorScope {
        ActorScope(adapter: adapter, grants: Set(Permission.allCases))
    }

    static let appUI = granted(.appUI)
    static let shareExtension = granted(.shareExtension)
}

extension Revision {
    static func r(_ value: Int) -> Revision { Revision(rawValue: value)! }
}

/// Deterministic identifiers: 00000000-0000-0000-0000-000000000001, …
func uuid(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}

final class SequentialOperationIDs: Sendable {
    private let counter = Mutex(0)

    func next() -> OperationID {
        OperationID(rawValue: uuid(1_000_000 + counter.withLock { value in
            value += 1
            return value
        }))
    }
}

extension OperationError {
    var denial: AuthorizationDenial? {
        if case .unauthorized(let denial) = self { denial } else { nil }
    }
}

/// A value shared with a fault hook or a concurrent task.
final class Locked<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    init(_ value: Value) { storage = Mutex(value) }

    var value: Value { storage.withLock { $0 } }

    func set(_ value: Value) { storage.withLock { $0 = value } }
}

// MARK: - Files

/// A directory removed when the value is released.
final class TemporaryDirectory: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "LabStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func file(_ name: String) -> URL { url.appending(path: name) }

    var storeURL: URL { file("store.sqlite") }
}

enum RepositoryFixtures {
    /// `Fixtures/` at the repository root, found from this source file.
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent() // LabStoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabStore
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository root
        .appending(path: "Fixtures")

    static let demoSeedURL = root.appending(path: "demo/seed.json")

    static func demoSeed() throws -> DemoSeed { try DemoFixture(contentsOf: demoSeedURL).seed }

    static func demoSeedData() throws -> Data { try Data(contentsOf: demoSeedURL) }
}

// MARK: - Raw file access

/// Every row of the store's tables, read through a separate connection, for exact comparisons.
struct DatabaseDump: Hashable, CustomStringConvertible {
    let collections: [[String]]
    let items: [[String]]
    /// Request IDs only: a receipt's body holds its operation ID, which differs between runs.
    let receiptRequests: [String]

    init(_ url: URL) throws {
        let database = try SQLiteDatabase(url: url)
        collections = try Self.rows(database, "SELECT * FROM collections ORDER BY id")
        items = try Self.rows(database, "SELECT * FROM items ORDER BY id")
        receiptRequests = try database.rows("SELECT request_id FROM receipts ORDER BY request_id") { $0.text(0) ?? "∅" }
    }

    static func rows(_ database: SQLiteDatabase, _ sql: String) throws -> [[String]] {
        try database.rows(sql) { row in
            (0..<row.columnCount).map { row.isNull($0) ? "∅" : row.text($0) ?? "∅" }
        }
    }

    var description: String { "collections: \(collections)\nitems: \(items)\nreceipts: \(receiptRequests)" }
}

extension SQLiteDatabase {
    func strings(_ sql: String) throws -> [String] { try rows(sql) { $0.text(0) ?? "∅" } }
}

// MARK: - Fault injection

extension SQLiteOperationStore {
    /// Opens a store whose transactions report every fault point to `hook`.
    static func open(_ url: URL, hook: FaultHook? = nil) async throws -> SQLiteOperationStore {
        try await SQLiteOperationStore(url: url, faultHook: hook)
    }
}

/// Records every fault point a store reaches and stops a transaction where a test asks, once.
final class FaultPlan: Sendable {
    private struct State {
        var seen: [FaultPoint] = []
        var interruptAtIndex: Int?
        var interruptWhere: (@Sendable (FaultPoint) -> Bool)?
        var observer: (@Sendable (FaultPoint) -> Void)?
    }

    private let state = Mutex(State())

    /// Stops at the `offset`-th fault point reached from now, counting from 0.
    func interrupt(atOffset offset: Int) {
        state.withLock { $0.interruptAtIndex = $0.seen.count + offset }
    }

    /// Stops at the next fault point that matches.
    func interrupt(where predicate: @escaping @Sendable (FaultPoint) -> Bool) {
        state.withLock { $0.interruptWhere = predicate }
    }

    /// Runs `body` at every fault point, inside the transaction, before the plan decides.
    func observe(_ body: (@Sendable (FaultPoint) -> Void)?) {
        state.withLock { $0.observer = body }
    }

    var seen: [FaultPoint] { state.withLock { $0.seen } }

    var hook: FaultHook {
        { [self] point in
            let (interrupt, observer) = state.withLock { state -> (Bool, (@Sendable (FaultPoint) -> Void)?) in
                let index = state.seen.count
                state.seen.append(point)
                if state.interruptAtIndex == index {
                    state.interruptAtIndex = nil
                    return (true, state.observer)
                }
                if let predicate = state.interruptWhere, predicate(point) {
                    state.interruptWhere = nil
                    return (true, state.observer)
                }
                return (false, state.observer)
            }
            observer?(point)
            return interrupt ? .interrupt : .proceed
        }
    }
}
