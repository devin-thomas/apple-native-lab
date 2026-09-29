import LabDomain

/// Why the persistent store could not open, read, or write.
///
/// Cases carry SQLite result codes but never paths, SQL, or record content, which can be private.
public enum StoreError: Error, Hashable, Sendable {
    /// The file could not be opened or created.
    case cannotOpen(code: Int32)
    /// The file is not this store's database. Nothing was changed.
    case notALabStore
    /// The file has a schema version this build does not know. Nothing was changed.
    case newerSchema(found: Int, supported: Int)
    /// A migration step failed. The file keeps the version it had before that step.
    case migrationFailed(toVersion: Int, code: Int32)
    case readFailed(code: Int32)
    /// The commit failed and none of its writes are visible.
    case writeFailed(code: Int32)
    /// Deterministic fault injection in a test stopped the transaction; nothing else produces it.
    /// Stopped before `COMMIT`, none of its writes are visible. Stopped after, the commit is
    /// durable and a retry of the same request returns the recorded receipt.
    case interrupted
    /// A stored row could not be read back as a valid entity or receipt.
    case corruptRecord
    /// The commit would have moved an entity between namespaces, put an item in a collection of
    /// another namespace, or removed an entity that is missing or user data. Nothing was written.
    case namespaceViolation(EntityReference)
}
