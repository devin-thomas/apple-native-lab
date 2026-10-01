import Foundation
import LabDomain

/// The iCloud account a ledger belongs to. Identity is an app-chosen UUID, never a name, an
/// Apple ID, or a CloudKit user record. Two ledgers with different account IDs never share
/// private records.
public struct AccountID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init() { rawValue = UUID() }

    public init?(uuidString: String) {
        guard let rawValue = UUID(uuidString: uuidString) else { return nil }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

/// One installation of the lab that authors mutations. App-generated and revocable, not a hardware
/// identifier.
public struct DeviceID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init() { rawValue = UUID() }

    public init?(uuidString: String) {
        guard let rawValue = UUID(uuidString: uuidString) else { return nil }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

/// A shared database the optional profile exchanges. Membership is an explicit list of account
/// IDs, not a display name.
public struct ShareID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init() { rawValue = UUID() }

    public init?(uuidString: String) {
        guard let rawValue = UUID(uuidString: uuidString) else { return nil }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

/// One synced record. The same identifier is the lab item's ID, so a record keeps its identity
/// across devices without using its title.
public struct RecordID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init() { rawValue = UUID() }

    public init?(uuidString: String) {
        guard let rawValue = UUID(uuidString: uuidString) else { return nil }
        self.rawValue = rawValue
    }

    public var itemID: ItemID { ItemID(rawValue: rawValue) }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}

/// One mutation in the write-ahead ledger. The same UUID is the domain request ID of the commit
/// that materializes it, so a replay returns the original receipt.
public struct MutationID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init() { rawValue = UUID() }

    public init?(uuidString: String) {
        guard let rawValue = UUID(uuidString: uuidString) else { return nil }
        self.rawValue = rawValue
    }

    public var requestID: RequestID { RequestID(rawValue: rawValue) }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}
