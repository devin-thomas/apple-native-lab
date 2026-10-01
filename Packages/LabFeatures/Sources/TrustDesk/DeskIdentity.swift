import Foundation

/// The stable identity of the desk fixture. A display name is what a person reads; it is not
/// this identifier, and renaming never allocates a new one.
public struct DeskIdentityID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public var description: String { rawValue.uuidString }

    /// The account name of this identity's keychain record, and the passkey user handle.
    /// Both are the identifier, so a display-name change leaves them in place.
    public var account: String { rawValue.uuidString }

    public var userHandle: Data { Data(rawValue.uuidString.utf8) }
}

/// One desk identity: a stable identifier plus a display name that may change.
public struct DeskIdentity: Hashable, Sendable {
    public let id: DeskIdentityID
    public let displayName: String

    public init(id: DeskIdentityID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    /// The same identity with a different display name.
    public func renaming(to displayName: String) -> DeskIdentity {
        DeskIdentity(id: id, displayName: displayName)
    }
}
