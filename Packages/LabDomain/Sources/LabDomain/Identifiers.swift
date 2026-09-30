import Foundation

/// The kinds of entity the domain stores. Each kind has its own identifier namespace.
public enum EntityKind: String, Codable, Sendable, CaseIterable {
    case collection
    case item
    /// A running-or-paused session that system surfaces show (LAB-004 Surface Deck).
    case session
    /// A finite piece of expensive work a person started, such as a render (LAB-032).
    case job
}

/// A stored domain value with a stable identity and a revision.
public protocol DomainEntity: Sendable, Hashable, Codable {
    static var kind: EntityKind { get }
    var revision: Revision { get }
}

/// A stable identifier for one kind of entity.
///
/// The `Entity` parameter makes an item ID and a collection ID different types, so one cannot be
/// passed where the other is expected. Identity is a UUID, never a title, URL, or list position:
/// renaming an entity leaves its ID unchanged, and two entities may share a title.
public struct EntityID<Entity: DomainEntity>: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    /// A new random identifier.
    public init() { rawValue = UUID() }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

public typealias CollectionID = EntityID<LabCollection>
public typealias ItemID = EntityID<LabItem>
public typealias SessionID = EntityID<LabSession>
public typealias JobID = EntityID<LabJob>

/// Names one requested decision. An adapter creates it once per user intent and reuses it on
/// every retry, so a retry returns the original receipt instead of mutating again.
public struct RequestID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init() { rawValue = UUID() }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

/// Identifies one admitted operation and its receipt. The service assigns it; callers never do.
public struct OperationID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init() { rawValue = UUID() }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

/// The version of one entity. It starts at 1 when the entity is created and increases by one with
/// every committed change, so it orders the states of that entity and nothing else.
public struct Revision: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: Int

    /// `nil` unless `rawValue` is at least 1.
    public init?(rawValue: Int) {
        guard rawValue >= 1 else { return nil }
        self.rawValue = rawValue
    }

    private init(unchecked value: Int) { rawValue = value }

    /// The revision of a newly created entity.
    public static let initial = Revision(unchecked: 1)

    /// The revision that follows this one.
    public func next() -> Revision { Revision(unchecked: rawValue + 1) }

    public static func < (lhs: Revision, rhs: Revision) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Int.self)
        guard let revision = Revision(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "A revision starts at 1.")
        }
        self = revision
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { String(rawValue) }
}

/// A typed reference to any stored entity, for receipts, conflicts, and errors.
public enum EntityReference: Hashable, Sendable, Codable, CustomStringConvertible {
    case collection(CollectionID)
    case item(ItemID)
    case session(SessionID)
    case job(JobID)

    public var kind: EntityKind {
        switch self {
        case .collection: .collection
        case .item: .item
        case .session: .session
        case .job: .job
        }
    }

    public var rawID: UUID {
        switch self {
        case .collection(let id): id.rawValue
        case .item(let id): id.rawValue
        case .session(let id): id.rawValue
        case .job(let id): id.rawValue
        }
    }

    public var description: String { "\(kind.rawValue) \(rawID.uuidString)" }

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        switch try container.decode(EntityKind.self, forKey: .kind) {
        case .collection: self = .collection(CollectionID(rawValue: id))
        case .item: self = .item(ItemID(rawValue: id))
        case .session: self = .session(SessionID(rawValue: id))
        case .job: self = .job(JobID(rawValue: id))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(rawID, forKey: .id)
    }
}
