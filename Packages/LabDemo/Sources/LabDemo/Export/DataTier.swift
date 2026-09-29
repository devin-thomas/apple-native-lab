/// The rights and privacy class of one artifact (docs/SECURITY_AND_PRIVACY.md, docs/ASSET_POLICY.md).
///
/// Every artifact in an evidence export declares one. Only `public-fixture` content is exported
/// without question. Anything else is refused unless the person records an explicit override,
/// and `sensitive` content is refused even then.
public enum DataTier: String, Hashable, Sendable, Codable, CaseIterable {
    /// Original, synthetic, redistributable project material, such as `Fixtures/`.
    case publicFixture = "public-fixture"
    /// Something a person created or imported. Private by default.
    case userPrivate = "user-private"
    /// Credentials, grants, recordings, room geometry, health samples, or model input. Never exported.
    case sensitive
    /// Rights not established. Treated as private until someone classifies it.
    case unclassified

    public var title: String {
        switch self {
        case .publicFixture: "Public fixture"
        case .userPrivate: "Private"
        case .sensitive: "Sensitive"
        case .unclassified: "Unclassified"
        }
    }

    /// Whether a recorded override can admit this tier. Sensitive content has no override.
    public var allowsOverride: Bool {
        switch self {
        case .publicFixture, .userPrivate, .unclassified: true
        case .sensitive: false
        }
    }
}
