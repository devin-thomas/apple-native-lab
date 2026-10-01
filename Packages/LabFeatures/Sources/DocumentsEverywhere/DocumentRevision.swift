import Foundation

/// A document's revision as Documents Everywhere tracks it: content and metadata separately.
///
/// This mirrors the File Provider idea of a content version and a metadata version
/// (`NSFileProviderItemVersion`), but it is a lab-owned value. An external content edit bumps
/// `content`; a rename or tag change bumps only `metadata`. Comparing both prevents a stale
/// writer from silently overwriting a newer document.
public struct DocumentRevision: Hashable, Sendable, Comparable, Codable {
    /// Increments when the document's bytes change.
    public let content: UInt64
    /// Increments when only metadata (name, tags, parent) changes.
    public let metadata: UInt64

    public static let initial = DocumentRevision(content: 1, metadata: 1)

    public init(content: UInt64, metadata: UInt64) {
        self.content = content
        self.metadata = metadata
    }

    /// Builds a revision from a portable object's integer `revision` field (content only).
    public init(documentRevision: Int) {
        let value = UInt64(max(documentRevision, 1))
        self.init(content: value, metadata: 1)
    }

    public static func < (lhs: DocumentRevision, rhs: DocumentRevision) -> Bool {
        if lhs.content != rhs.content { return lhs.content < rhs.content }
        return lhs.metadata < rhs.metadata
    }

    /// A content edit: content moves forward; metadata is unchanged.
    public func afterContentEdit() -> DocumentRevision {
        DocumentRevision(content: content &+ 1, metadata: metadata)
    }

    /// A metadata-only edit: metadata moves forward; content is unchanged.
    public func afterMetadataEdit() -> DocumentRevision {
        DocumentRevision(content: content, metadata: metadata &+ 1)
    }

    /// Opaque bytes for File Provider item versions: 8 bytes content, then 8 bytes metadata, big-endian.
    public var contentVersionData: Data {
        var value = content.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
    }

    public var metadataVersionData: Data {
        var value = metadata.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
    }

    public static func from(contentVersion: Data, metadataVersion: Data) -> DocumentRevision? {
        guard let content = UInt64(bigEndianData: contentVersion),
              let metadata = UInt64(bigEndianData: metadataVersion)
        else { return nil }
        return DocumentRevision(content: content, metadata: metadata)
    }
}

/// What an external edit changed.
public enum ExternalChange: Hashable, Sendable {
    case content
    case metadata
}

/// The outcome of applying an external edit under revision rules.
public enum RevisionDecision: Hashable, Sendable {
    /// The edit applies; the document moves to this revision.
    case accepted(DocumentRevision)
    /// The base revision the editor held does not match what the lab holds.
    case conflict(expected: DocumentRevision, found: DocumentRevision)
    /// The editor's base matches and the change is a no-op.
    case unchanged
}

/// Rules for external edits: a matching base revision is required; a mismatch never overwrites.
public enum RevisionRules {
    /// Applies `change` when the editor's `base` equals `current`. Otherwise returns a conflict
    /// that leaves `current` untouched.
    public static func apply(
        current: DocumentRevision,
        base: DocumentRevision,
        change: ExternalChange
    ) -> RevisionDecision {
        guard base == current else {
            return .conflict(expected: base, found: current)
        }
        switch change {
        case .content: return .accepted(current.afterContentEdit())
        case .metadata: return .accepted(current.afterMetadataEdit())
        }
    }
}

private extension UInt64 {
    init?(bigEndianData data: Data) {
        guard data.count == MemoryLayout<UInt64>.size else { return nil }
        var value: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            data.copyBytes(to: buffer)
        }
        self = UInt64(bigEndian: value)
    }
}
