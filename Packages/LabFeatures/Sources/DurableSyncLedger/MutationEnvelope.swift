import Foundation
import LabDomain

/// Where a record is exchanged. There is no public-database case: personal fixtures never go to
/// a public CloudKit database, and the type cannot name one.
public enum RecordScope: String, Codable, Sendable, CaseIterable {
    case `private`
    case shared
}

/// The change an envelope carries. A tombstone is the deletion. An older upsert must not bring
/// the record back once a later tombstone is in the ledger.
public enum MutationKind: Hashable, Sendable {
    case upsert(title: String, note: String)
    case tombstone

    public var isTombstone: Bool {
        if case .tombstone = self { return true }
        return false
    }
}

extension MutationKind: Codable {
    private enum CodingKeys: String, CodingKey { case type, title, note }
    private enum Kind: String, Codable { case upsert, tombstone }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .upsert:
            self = .upsert(
                title: try container.decode(String.self, forKey: .title),
                note: try container.decode(String.self, forKey: .note)
            )
        case .tombstone:
            if container.contains(.title) || container.contains(.note) {
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: container, debugDescription: "A deletion carries no title or note."
                )
            }
            self = .tombstone
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .upsert(let title, let note):
            try container.encode(Kind.upsert, forKey: .type)
            try container.encode(title, forKey: .title)
            try container.encode(note, forKey: .note)
        case .tombstone:
            try container.encode(Kind.tombstone, forKey: .type)
        }
    }
}

/// One durable mutation: who wrote it, what they had seen, and the record's new value or its
/// deletion. The ledger appends the envelope before the lab store is changed.
public struct MutationEnvelope: Hashable, Sendable, Codable, Identifiable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let id: MutationID
    public let record: RecordID
    public let account: AccountID
    public let device: DeviceID
    public let scope: RecordScope
    public let share: ShareID?
    public let vector: VersionVector
    public let kind: MutationKind

    public init(
        schemaVersion: Int = MutationEnvelope.schemaVersion,
        id: MutationID,
        record: RecordID,
        account: AccountID,
        device: DeviceID,
        scope: RecordScope,
        share: ShareID?,
        vector: VersionVector,
        kind: MutationKind
    ) throws(LedgerError) {
        guard schemaVersion == Self.schemaVersion else {
            throw .invalidMutation("This edit uses schema \(schemaVersion), and this build reads schema \(Self.schemaVersion).")
        }
        switch scope {
        case .private:
            guard share == nil else { throw .invalidMutation("A private edit names no shared database.") }
        case .shared:
            guard share != nil else { throw .invalidMutation("A shared edit names its shared database.") }
        }
        guard (vector.counters[device] ?? 0) >= 1 else {
            throw .invalidMutation("An edit's version vector has to include the device that wrote it.")
        }
        let storedKind: MutationKind
        switch kind {
        case .upsert(let title, let note):
            let validTitle: EntityTitle
            let validNote: ItemNote
            do {
                validTitle = try EntityTitle(title)
                validNote = try ItemNote(note)
            } catch {
                throw .invalidMutation(LedgerError.describe(error))
            }
            storedKind = .upsert(title: validTitle.value, note: validNote.value)
        case .tombstone:
            storedKind = .tombstone
        }
        self.schemaVersion = schemaVersion
        self.id = id
        self.record = record
        self.account = account
        self.device = device
        self.scope = scope
        self.share = share
        self.vector = vector
        self.kind = storedKind
    }

    public var title: String? {
        if case .upsert(let title, _) = kind { return title }
        return nil
    }

    public var note: String? {
        if case .upsert(_, let note) = kind { return note }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, record, account, device, scope, share, vector, kind
    }

    public init(from decoder: any Decoder) throws {
        try LedgerCoding.rejectUnknownFields(
            in: decoder,
            allowed: ["schemaVersion", "id", "record", "account", "device", "scope", "share", "vector", "kind"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            id: container.decode(MutationID.self, forKey: .id),
            record: container.decode(RecordID.self, forKey: .record),
            account: container.decode(AccountID.self, forKey: .account),
            device: container.decode(DeviceID.self, forKey: .device),
            scope: container.decode(RecordScope.self, forKey: .scope),
            share: container.decodeIfPresent(ShareID.self, forKey: .share),
            vector: container.decode(VersionVector.self, forKey: .vector),
            kind: container.decode(MutationKind.self, forKey: .kind)
        )
    }
}

/// Both versions of one record that were edited apart. Neither is written over the other.
public struct ConflictRecord: Hashable, Sendable, Identifiable {
    public var id: RecordID { record }
    public let record: RecordID
    /// Every edit that no other edit happened after, tombstones included.
    public let edits: [MutationEnvelope]
    /// The value still stored, when one was committed before the conflict. Nil when nothing is stored.
    public let storedTitle: String?
    public let storedNote: String?
    public let storedIsDeleted: Bool
    public let explanation: String
}

/// Why the ledger left a record in its current state. The sentence is the explanation a person reads.
public struct LedgerDecision: Hashable, Sendable, Identifiable {
    public let id: MutationID
    public let record: RecordID
    public let explanation: String
    /// The domain receipt's summary, when materializing the decision committed one.
    public let receiptSummary: String?
}

/// What a person sees for one record after reconciliation.
public enum RecordState: Hashable, Sendable {
    case absent
    case live(title: String, note: String)
    case deleted
    case conflict(ConflictRecord)
}
