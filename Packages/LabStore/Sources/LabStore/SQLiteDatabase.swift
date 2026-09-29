import Foundation
import SQLite3

/// A failed SQLite call. `message` is for tests and local debugging only; it can name tables and
/// columns, so it never leaves this module inside a public error.
struct SQLiteError: Error, CustomStringConvertible {
    let code: Int32
    let message: String

    /// The primary result code, without the extended bits.
    var primaryCode: Int32 { code & 0xFF }

    var description: String { "SQLite \(code): \(message)" }
}

/// One SQLite connection, used synchronously by a single owner.
///
/// It is not thread-safe. `SQLiteOperationStore` owns one and touches it only on its own serial
/// queue; tests use one on a single task.
final class SQLiteDatabase {
    private let handle: OpaquePointer

    /// Opens or creates the file with foreign keys enforced and a busy timeout for writers in
    /// other connections or processes.
    init(url: URL, busyTimeout: Duration = .seconds(5)) throws(SQLiteError) {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let status = sqlite3_open_v2(url.path(percentEncoded: false), &opened, flags, nil)
        guard status == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close_v2(opened)
            throw SQLiteError(code: status, message: message)
        }
        handle = opened
        sqlite3_extended_result_codes(handle, 1)
        let milliseconds = busyTimeout.components.seconds * 1_000 + busyTimeout.components.attoseconds / 1_000_000_000_000_000
        sqlite3_busy_timeout(handle, Int32(clamping: milliseconds))
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs one or more statements that return no rows.
    func execute(_ sql: String) throws(SQLiteError) {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if status != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? lastMessage
            sqlite3_free(errorMessage)
            throw SQLiteError(code: status, message: message)
        }
    }

    func prepare(_ sql: String) throws(SQLiteError) -> SQLiteStatement {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v3(handle, sql, -1, 0, &statement, nil)
        guard status == SQLITE_OK, let statement else { throw error(status) }
        return SQLiteStatement(statement, database: self)
    }

    /// Runs a query and maps every row.
    func rows<Row>(
        _ sql: String,
        _ bindings: [SQLiteValue] = [],
        map: (SQLiteStatement) throws(SQLiteError) -> Row
    ) throws(SQLiteError) -> [Row] {
        let statement = try prepare(sql)
        try statement.bind(bindings)
        var rows: [Row] = []
        while try statement.step() {
            rows.append(try map(statement))
        }
        return rows
    }

    /// Runs a statement that returns no rows and reports how many rows it changed.
    @discardableResult
    func run(_ sql: String, _ bindings: [SQLiteValue] = []) throws(SQLiteError) -> Int {
        let statement = try prepare(sql)
        try statement.bind(bindings)
        while try statement.step() {}
        return Int(sqlite3_changes(handle))
    }

    func integer(_ sql: String) throws(SQLiteError) -> Int {
        try rows(sql) { $0.integer(0) }.first ?? 0
    }

    /// Whether no transaction is open on this connection.
    var isAutocommit: Bool { sqlite3_get_autocommit(handle) != 0 }

    /// Ends an open transaction without keeping its writes. Safe to call when SQLite already
    /// rolled the transaction back after an error.
    func rollbackIfNeeded() {
        guard !isAutocommit else { return }
        sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
    }

    fileprivate var lastMessage: String { String(cString: sqlite3_errmsg(handle)) }

    fileprivate func error(_ status: Int32) -> SQLiteError {
        let extended = sqlite3_extended_errcode(handle)
        return SQLiteError(code: extended == SQLITE_OK ? status : extended, message: lastMessage)
    }
}

enum SQLiteValue {
    case integer(Int)
    case text(String)
}

/// A prepared statement. It is finalized when released.
final class SQLiteStatement {
    private let statement: OpaquePointer
    private let database: SQLiteDatabase

    fileprivate init(_ statement: OpaquePointer, database: SQLiteDatabase) {
        self.statement = statement
        self.database = database
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ values: [SQLiteValue]) throws(SQLiteError) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status = switch value {
            case .integer(let number): sqlite3_bind_int64(statement, index, Int64(number))
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, Self.transient)
            }
            guard status == SQLITE_OK else { throw database.error(status) }
        }
    }

    /// Advances to the next row. Returns `false` when the statement is done.
    func step() throws(SQLiteError) -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        case let status: throw database.error(status)
        }
    }

    var columnCount: Int32 { sqlite3_column_count(statement) }

    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }

    func integer(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }

    func text(_ column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
    }

    /// Tells SQLite to copy bound text before `bind` returns.
    private static var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }
}
