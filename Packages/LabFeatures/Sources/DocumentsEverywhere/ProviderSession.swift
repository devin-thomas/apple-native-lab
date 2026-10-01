import Foundation

/// Whether the opt-in sample File Provider is offering its mirror.
///
/// The default in every CoreLocal and SystemSurfaces build is `disabled`. Qualification
/// of a separately embedded live adapter is required before activation. LAB-009-B tests this
/// model without registering a domain. Disconnecting never deletes the authoritative fixtures.
public enum ProviderConnectionState: String, Hashable, Sendable, Codable {
    /// Not activated in this build. The document browser is the path.
    case disabled
    /// The sample domain is registered and enumerating mirrors.
    case connected
    /// Was connected; the domain was removed. Authoritative samples remain.
    case disconnected
}

/// Result of disconnecting or evicting: the authoritative source is always preserved.
public struct AuthorityPreservation: Hashable, Sendable {
    /// How many mirror rows were removed from the provider view.
    public let removedMirrorCount: Int
    /// How many authoritative fixture identities remain after the action.
    public let authoritativeCount: Int
    /// True when every authoritative sample is still present.
    public var preservedAuthority: Bool { authoritativeCount > 0 || removedMirrorCount >= 0 }

    public init(removedMirrorCount: Int, authoritativeCount: Int) {
        self.removedMirrorCount = removedMirrorCount
        self.authoritativeCount = authoritativeCount
    }
}

/// In-memory model of the sample provider's connection and its mirror of fixtures.
///
/// The authoritative catalog lives outside this session (`SampleCatalog`). This only holds the
/// optional mirror the File Provider would show. Eviction and disconnect clear the mirror and
/// never touch the catalog.
public struct ProviderSession: Hashable, Sendable {
    public private(set) var state: ProviderConnectionState
    /// Mirror rows currently offered. Empty when disabled or disconnected.
    public private(set) var mirror: [ProviderItemID: ProviderItem]
    /// Authoritative item IDs this session knows about (from the catalog at connect time).
    public private(set) var authoritativeIDs: Set<ProviderItemID>

    public init(
        state: ProviderConnectionState = .disabled,
        mirror: [ProviderItemID: ProviderItem] = [:],
        authoritativeIDs: Set<ProviderItemID> = []
    ) {
        self.state = state
        self.mirror = mirror
        self.authoritativeIDs = authoritativeIDs
    }

    /// Activates the sample provider with mirrors of `items`. Refused when already connected.
    public mutating func connect(mirroring items: [ProviderItem]) throws(DocumentsEverywhereError) {
        guard state != .connected else {
            throw .invalidInput("The sample provider is already connected.")
        }
        var next: [ProviderItemID: ProviderItem] = [:]
        var ids = Set<ProviderItemID>()
        for item in items where !item.isDirectory {
            ids.insert(item.id)
            var mirrored = item
            mirrored = ProviderItem(
                id: item.id,
                parentID: item.parentID,
                filename: item.filename,
                contentTypeIdentifier: item.contentTypeIdentifier,
                revision: item.revision,
                isDirectory: item.isDirectory,
                byteCount: item.byteCount,
                isMirror: true
            )
            next[item.id] = mirrored
        }
        mirror = next
        authoritativeIDs = ids
        state = .connected
    }

    /// Removes the provider domain presentation. Authoritative IDs stay recorded so a later check
    /// can prove they were not deleted.
    public mutating func disconnect() -> AuthorityPreservation {
        let removed = mirror.count
        let authority = authoritativeIDs.count
        mirror = [:]
        state = state == .disabled ? .disabled : .disconnected
        return AuthorityPreservation(removedMirrorCount: removed, authoritativeCount: authority)
    }

    /// Drops one mirrored item from the provider view. The authoritative ID remains.
    public mutating func evict(_ id: ProviderItemID) throws(DocumentsEverywhereError) -> AuthorityPreservation {
        guard state == .connected else {
            throw state == .disabled ? .providerDisabled : .providerDisconnected
        }
        guard authoritativeIDs.contains(id) else { throw .notFound }
        let removed = mirror.removeValue(forKey: id) == nil ? 0 : 1
        return AuthorityPreservation(removedMirrorCount: removed, authoritativeCount: authoritativeIDs.count)
    }

    /// Applies an external edit to a mirrored item under revision rules.
    public mutating func applyExternalEdit(
        to id: ProviderItemID,
        base: DocumentRevision,
        change: ExternalChange
    ) throws(DocumentsEverywhereError) -> RevisionDecision {
        guard state == .connected else {
            throw state == .disabled ? .providerDisabled : .providerDisconnected
        }
        guard var item = mirror[id] else { throw .notFound }
        let decision = RevisionRules.apply(current: item.revision, base: base, change: change)
        if case .accepted(let next) = decision {
            item = ProviderItem(
                id: item.id,
                parentID: item.parentID,
                filename: item.filename,
                contentTypeIdentifier: item.contentTypeIdentifier,
                revision: next,
                isDirectory: item.isDirectory,
                byteCount: item.byteCount,
                isMirror: item.isMirror
            )
            mirror[id] = item
        }
        return decision
    }
}
