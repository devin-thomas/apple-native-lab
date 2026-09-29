import Foundation

/// Where staged imports wait for a person to review them.
///
/// The file-system implementation is `StagingArea` in the `LabStaging` package, which a share
/// extension and the app open on the same folder. `InMemoryStagingInbox` is the reference.
public protocol StagingInbox: Sendable {
    /// Reads a waiting record back and validates it again from its bytes, and for files from
    /// the staged content. A record that no longer validates is moved to quarantine, where it
    /// cannot block a later import, and the rejection is thrown.
    func validatedRecord(_ id: StagingID) async throws(ImportRejection) -> StagingRecord

    /// Removes an adopted record and its staged content. Removing one already gone succeeds, so
    /// a retried adoption finishes cleanly.
    func markAdopted(_ id: StagingID) async throws(ImportRejection)
}

/// What staging did with new content.
public enum StagingOutcome: Hashable, Sendable {
    case staged(StagingID)
    /// The same content, by digest, is already waiting. Nothing new was stored.
    case duplicate(StagingID)

    public var id: StagingID {
        switch self {
        case .staged(let id), .duplicate(let id): id
        }
    }
}

/// A staging inbox in memory, for tests, previews, and the reference behavior. It keeps each
/// record's encoded bytes, as a file would, and validates them again when they are read.
public actor InMemoryStagingInbox: StagingInbox {
    private let limits: ImportLimits
    private var waiting: [StagingID: Data] = [:]
    private var arrivalOrder: [StagingID] = []
    private var setAside: [(id: StagingID, reason: ImportRejection)] = []

    public init(limits: ImportLimits = .standard) {
        self.limits = limits
    }

    /// Stages a record, or reports the waiting copy of the same content.
    public func stage(_ record: StagingRecord) -> StagingOutcome {
        if waiting[record.id] != nil { return .duplicate(record.id) }
        waiting[record.id] = record.encoded()
        arrivalOrder.append(record.id)
        return .staged(record.id)
    }

    /// Stores bytes under `id` as a writer might have, damaged or forged ones included.
    public func storeUnchecked(_ data: Data, as id: StagingID) {
        if waiting[id] == nil { arrivalOrder.append(id) }
        waiting[id] = data
    }

    /// Waiting records, oldest first.
    public var waitingIDs: [StagingID] { arrivalOrder.filter { waiting[$0] != nil } }

    public var quarantined: [(id: StagingID, reason: ImportRejection)] { setAside }

    public func validatedRecord(_ id: StagingID) throws(ImportRejection) -> StagingRecord {
        guard let data = waiting[id] else { throw .notFound }
        do throws(ImportRejection) {
            let record = try StagingRecord(decoding: data, limits: limits)
            guard record.id == id else { throw .digestMismatch }
            return record
        } catch {
            waiting[id] = nil
            setAside.append((id, error))
            throw error
        }
    }

    public func markAdopted(_ id: StagingID) {
        waiting[id] = nil
    }

    /// Removes a record a person chose not to import.
    public func discard(_ id: StagingID) {
        waiting[id] = nil
    }
}
