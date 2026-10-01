import Foundation

/// Stable identity of one item in the sample provider or the in-app catalog.
///
/// Lab-owned: not an `NSFileProviderItemIdentifier`. The File Provider adapter maps these to
/// provider identifiers; the document browser uses them directly.
public struct ProviderItemID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let root = ProviderItemID(rawValue: "root")
}

/// One enumerable document or folder in Documents Everywhere.
public struct ProviderItem: Hashable, Sendable, Codable {
    public let id: ProviderItemID
    public let parentID: ProviderItemID
    public let filename: String
    /// A UTType identifier such as `public.json` or the lab object type. Never a path.
    public let contentTypeIdentifier: String
    public let revision: DocumentRevision
    public let isDirectory: Bool
    public let byteCount: Int?
    /// When true, this row is a mirror of an authoritative fixture, not the authority itself.
    public let isMirror: Bool

    public init(
        id: ProviderItemID,
        parentID: ProviderItemID = .root,
        filename: String,
        contentTypeIdentifier: String,
        revision: DocumentRevision = .initial,
        isDirectory: Bool = false,
        byteCount: Int? = nil,
        isMirror: Bool = false
    ) {
        self.id = id
        self.parentID = parentID
        self.filename = filename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.revision = revision
        self.isDirectory = isDirectory
        self.byteCount = byteCount
        self.isMirror = isMirror
    }
}
