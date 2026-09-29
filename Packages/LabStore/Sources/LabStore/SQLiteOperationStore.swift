import Dispatch
import Foundation
import LabDomain
import SQLite3

/// The persistent `OperationStore`: one SQLite file, opened through the system SQLite library.
///
/// `apply(_:)` runs the store contract inside one `BEGIN IMMEDIATE` transaction. The receipt check
/// and every revision precondition are read while this connection holds the database's write
/// lock, so a writer in another connection or process can neither slip in between the check and
/// the write nor see a partial commit. The file uses write-ahead logging with
/// `synchronous = FULL`: a transaction that did not commit leaves nothing behind after a crash,
/// and a commit that returned survives the app or the system stopping. (`fullfsync` is off, so
/// the most recent commits are not promised to survive sudden power loss; the file stays
/// consistent either way.)
///
/// The actor runs on its own serial dispatch queue rather than the shared cooperative pool,
/// because SQLite calls block, including while waiting up to five seconds for another writer.
///
/// Opening a file creates it or migrates it to `schemaVersion` first. A file from a newer build,
/// or one that is not this store's, is refused without being changed.
public actor SQLiteOperationStore: OperationStore {
    /// The schema version this build reads and writes.
    public static let schemaVersion = StoreSchema.currentVersion

    private let queue: DispatchSerialQueue
    private let database: SQLiteDatabase
    private var faultHook: FaultHook?

    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// Opens the store at `url`, creating the file or migrating it as needed.
    public init(url: URL) async throws(StoreError) {
        try await self.init(url: url, faultHook: nil)
    }

    init(url: URL, faultHook: FaultHook?) async throws(StoreError) {
        let queue = DispatchSerialQueue(label: "LabStore.SQLiteOperationStore")
        let opened: Result<SQLiteDatabase, StoreError> = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Result { () throws(StoreError) in
                    try Self.openAndMigrate(url, faultHook: faultHook)
                })
            }
        }
        self.queue = queue
        database = try opened.get()
        self.faultHook = faultHook
    }

    // MARK: Reads

    public func collections() throws(StoreError) -> [LabCollection] {
        try entities(read { try database.rows("SELECT \(Self.collectionColumns) FROM collections", map: Self.collection) })
    }

    public func collection(_ id: CollectionID) throws(StoreError) -> LabCollection? {
        try entities(read {
            try database.rows(
                "SELECT \(Self.collectionColumns) FROM collections WHERE id = ?1", [.text(id.rawValue.uuidString)], map: Self.collection
            )
        }).first
    }

    public func item(_ id: ItemID) throws(StoreError) -> LabItem? {
        try entities(read {
            try database.rows("SELECT \(Self.itemColumns) FROM items WHERE id = ?1", [.text(id.rawValue.uuidString)], map: Self.item)
        }).first
    }

    public func items(in collectionID: CollectionID?) throws(StoreError) -> [LabItem] {
        guard let collectionID else {
            return try entities(read { try database.rows("SELECT \(Self.itemColumns) FROM items", map: Self.item) })
        }
        return try entities(read {
            try database.rows(
                "SELECT \(Self.itemColumns) FROM items WHERE collection_id = ?1", [.text(collectionID.rawValue.uuidString)], map: Self.item
            )
        })
    }

    public func receipt(for requestID: RequestID) throws(StoreError) -> ActionReceipt? {
        try recordedReceipt(for: requestID)
    }

    // MARK: Commit

    public func apply(_ commit: AuthorizedCommit) throws(StoreError) -> CommitOutcome {
        do {
            return try write(commit)
        } catch {
            database.rollbackIfNeeded()
            throw error
        }
    }

    /// The store contract, in order, inside one write transaction. There is no suspension point
    /// here, so the actor never interleaves another call with a commit.
    private func write(_ commit: AuthorizedCommit) throws(StoreError) -> CommitOutcome {
        try change(nil) { try database.execute("BEGIN IMMEDIATE") }
        try checkpoint(.began)

        if let recorded = try recordedReceipt(for: commit.requestID) {
            database.rollbackIfNeeded()
            return .duplicateRequest(recorded)
        }
        try checkpoint(.receiptChecked)

        for precondition in commit.preconditions {
            let actual = try revision(of: precondition.entity)
            if actual != precondition.expected {
                database.rollbackIfNeeded()
                return .preconditionFailed(precondition, actual: actual)
            }
        }
        try checkpoint(.preconditionsChecked)

        for collection in commit.collections {
            try upsert(collection)
            try checkpoint(.wrote(collection.reference))
        }
        for item in commit.items {
            try upsert(item)
            try checkpoint(.wrote(item.reference))
        }
        for entity in commit.removals {
            try remove(entity)
            try checkpoint(.removed(entity))
        }
        try record(commit.receipt)
        try checkpoint(.receiptRecorded)

        try change(nil) { try database.execute("COMMIT") }
        try checkpoint(.committed)
        return .applied
    }

    private func upsert(_ collection: LabCollection) throws(StoreError) {
        try change(collection.reference) {
            try database.run(
                """
                INSERT INTO collections (id, title, is_archived, revision, namespace) VALUES (?1, ?2, ?3, ?4, ?5)
                ON CONFLICT (id) DO UPDATE SET title = excluded.title, is_archived = excluded.is_archived,
                    revision = excluded.revision, namespace = excluded.namespace
                """,
                [
                    .text(collection.id.rawValue.uuidString), .text(collection.title.value),
                    .integer(collection.isArchived ? 1 : 0), .integer(collection.revision.rawValue),
                    .text(collection.namespace.rawValue),
                ]
            )
        }
    }

    private func upsert(_ item: LabItem) throws(StoreError) {
        try change(item.reference) {
            try database.run(
                """
                INSERT INTO items (id, collection_id, title, note, is_archived, revision, namespace)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                ON CONFLICT (id) DO UPDATE SET collection_id = excluded.collection_id, title = excluded.title,
                    note = excluded.note, is_archived = excluded.is_archived, revision = excluded.revision,
                    namespace = excluded.namespace
                """,
                [
                    .text(item.id.rawValue.uuidString), .text(item.collectionID.rawValue.uuidString),
                    .text(item.title.value), .text(item.note.value), .integer(item.isArchived ? 1 : 0),
                    .integer(item.revision.rawValue), .text(item.namespace.rawValue),
                ]
            )
        }
    }

    /// Deletes one demo entity. The `namespace` condition means a user row is never matched, and
    /// the schema's triggers refuse a user deletion from any other path too.
    private func remove(_ entity: EntityReference) throws(StoreError) {
        let table = switch entity {
        case .collection: "collections"
        case .item: "items"
        }
        let removed = try change(entity) {
            try database.run("DELETE FROM \(table) WHERE id = ?1 AND namespace = 'demo'", [.text(entity.rawID.uuidString)])
        }
        guard removed == 1 else { throw .namespaceViolation(entity) }
    }

    private func record(_ receipt: ActionReceipt) throws(StoreError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let body = try? encoder.encode(receipt) else { throw .corruptRecord }
        try change(nil) {
            try database.run(
                "INSERT INTO receipts (request_id, operation_id, body) VALUES (?1, ?2, ?3)",
                [
                    .text(receipt.requestID.rawValue.uuidString), .text(receipt.operationID.rawValue.uuidString),
                    .text(String(decoding: body, as: UTF8.self)),
                ]
            )
        }
    }

    private func recordedReceipt(for requestID: RequestID) throws(StoreError) -> ActionReceipt? {
        let bodies = try read {
            try database.rows("SELECT body FROM receipts WHERE request_id = ?1", [.text(requestID.rawValue.uuidString)]) { $0.text(0) }
        }
        guard let stored = bodies.first else { return nil }
        guard let body = stored,
              let receipt = try? JSONDecoder().decode(ActionReceipt.self, from: Data(body.utf8)),
              receipt.requestID == requestID
        else { throw .corruptRecord }
        return receipt
    }

    private func revision(of entity: EntityReference) throws(StoreError) -> Revision? {
        let table = switch entity {
        case .collection: "collections"
        case .item: "items"
        }
        let values = try read {
            try database.rows("SELECT revision FROM \(table) WHERE id = ?1", [.text(entity.rawID.uuidString)]) { $0.integer(0) }
        }
        guard let value = values.first else { return nil }
        guard let revision = Revision(rawValue: value) else { throw .corruptRecord }
        return revision
    }

    // MARK: Rows

    private static let collectionColumns = "id, title, is_archived, revision, namespace"
    private static let itemColumns = "id, collection_id, title, note, is_archived, revision, namespace"

    private static func collection(_ row: SQLiteStatement) -> LabCollection? {
        guard let id = row.text(0).flatMap(UUID.init(uuidString:)),
              let title = row.text(1).flatMap({ try? EntityTitle($0) }),
              let revision = Revision(rawValue: row.integer(3)),
              let namespace = row.text(4).flatMap(DataNamespace.init(rawValue:))
        else { return nil }
        return LabCollection(
            id: CollectionID(rawValue: id), title: title, isArchived: row.integer(2) != 0, revision: revision, namespace: namespace
        )
    }

    private static func item(_ row: SQLiteStatement) -> LabItem? {
        guard let id = row.text(0).flatMap(UUID.init(uuidString:)),
              let collectionID = row.text(1).flatMap(UUID.init(uuidString:)),
              let title = row.text(2).flatMap({ try? EntityTitle($0) }),
              let note = row.text(3).flatMap({ try? ItemNote($0) }),
              let revision = Revision(rawValue: row.integer(5)),
              let namespace = row.text(6).flatMap(DataNamespace.init(rawValue:))
        else { return nil }
        return LabItem(
            id: ItemID(rawValue: id), collectionID: CollectionID(rawValue: collectionID), title: title, note: note,
            isArchived: row.integer(4) != 0, revision: revision, namespace: namespace
        )
    }

    /// Every row as an entity, or `corruptRecord` when any row is not a valid one.
    private func entities<Entity>(_ rows: [Entity?]) throws(StoreError) -> [Entity] {
        var entities: [Entity] = []
        entities.reserveCapacity(rows.count)
        for row in rows {
            guard let row else { throw .corruptRecord }
            entities.append(row)
        }
        return entities
    }

    // MARK: Errors and fault points

    private func read<Value>(_ body: () throws -> Value) throws(StoreError) -> Value {
        do { return try body() } catch { throw .readFailed(code: Self.code(of: error)) }
    }

    /// Runs a write. A trigger refusing a namespace rule becomes `namespaceViolation`.
    @discardableResult
    private func change<Value>(_ entity: EntityReference?, _ body: () throws -> Value) throws(StoreError) -> Value {
        do {
            return try body()
        } catch {
            if let entity, let error = error as? SQLiteError, error.message.hasPrefix("lab-namespace") {
                throw .namespaceViolation(entity)
            }
            throw .writeFailed(code: Self.code(of: error))
        }
    }

    private static func code(of error: any Error) -> Int32 { (error as? SQLiteError)?.code ?? SQLITE_ERROR }

    private func checkpoint(_ point: FaultPoint) throws(StoreError) {
        if faultHook?(point) == .interrupt { throw .interrupted }
    }

    /// Replaces the fault hook. Tests only.
    func setFaultHook(_ hook: FaultHook?) {
        faultHook = hook
    }

    /// Runs statements on this store's connection, such as a pragma a test needs. Tests only.
    func execute(_ sql: String) throws(StoreError) {
        try change(nil) { try database.execute(sql) }
    }

    // MARK: Opening

    private static func openAndMigrate(_ url: URL, faultHook: FaultHook?) throws(StoreError) -> SQLiteDatabase {
        let database: SQLiteDatabase
        do { database = try SQLiteDatabase(url: url) } catch { throw .cannotOpen(code: error.code) }
        try checkIdentity(of: database)
        let journalMode: String?
        do {
            journalMode = try database.rows("PRAGMA journal_mode = WAL") { $0.text(0) }.first ?? nil
            try database.execute("PRAGMA synchronous = FULL")
        } catch {
            throw .cannotOpen(code: error.code)
        }
        guard journalMode == "wal" else { throw .cannotOpen(code: SQLITE_CANTOPEN) }
        try migrate(database, faultHook: faultHook)
        return database
    }

    /// Refuses a file that belongs to something else or to a newer build, before changing it.
    private static func checkIdentity(of database: SQLiteDatabase) throws(StoreError) {
        let applicationID: Int
        let version: Int
        let objects: Int
        do {
            applicationID = try database.integer("PRAGMA application_id")
            version = try database.integer("PRAGMA user_version")
            objects = try database.integer("SELECT count(*) FROM sqlite_schema")
        } catch {
            throw error.primaryCode == SQLITE_NOTADB ? .notALabStore : .cannotOpen(code: error.code)
        }
        let isNewFile = applicationID == 0 && version == 0 && objects == 0
        guard applicationID == StoreSchema.applicationID || isNewFile else { throw .notALabStore }
        guard version <= StoreSchema.currentVersion else {
            throw .newerSchema(found: version, supported: StoreSchema.currentVersion)
        }
    }

    /// Applies each missing migration in its own write transaction.
    private static func migrate(_ database: SQLiteDatabase, faultHook: FaultHook?) throws(StoreError) {
        for migration in StoreSchema.migrations {
            var interrupted = false
            do {
                guard try database.integer("PRAGMA user_version") < migration.version else { continue }
                try database.execute("BEGIN IMMEDIATE")
                // Another process may have migrated while this one waited for the lock.
                guard try database.integer("PRAGMA user_version") < migration.version else {
                    database.rollbackIfNeeded()
                    continue
                }
                try database.execute(migration.sql)
                try database.execute("PRAGMA user_version = \(migration.version)")
                try database.execute("PRAGMA application_id = \(StoreSchema.applicationID)")
                interrupted = faultHook?(.migrationWritten(version: migration.version)) == .interrupt
                if !interrupted { try database.execute("COMMIT") }
            } catch {
                database.rollbackIfNeeded()
                throw .migrationFailed(toVersion: migration.version, code: error.code)
            }
            if interrupted {
                database.rollbackIfNeeded()
                throw .interrupted
            }
        }
    }
}

// MARK: - Deterministic fault injection

/// A point inside a store transaction at which a test can observe or stop it.
enum FaultPoint: Hashable, Sendable {
    case began
    case receiptChecked
    case preconditionsChecked
    case wrote(EntityReference)
    case removed(EntityReference)
    case receiptRecorded
    /// After `COMMIT` returned. Stopping here models a process that ends before it can report
    /// the result: the commit is durable, and the caller sees an error.
    case committed
    /// A migration's statements ran and its transaction is still open.
    case migrationWritten(version: Int)
}

enum FaultAction: Sendable {
    case proceed
    case interrupt
}

typealias FaultHook = @Sendable (FaultPoint) -> FaultAction
