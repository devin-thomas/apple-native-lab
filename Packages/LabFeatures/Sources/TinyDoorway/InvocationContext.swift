import Foundation

/// Where a doorway invocation came from and what the host knew about the network.
///
/// A context never carries a grant or an operation. It is only the untrusted input the validator
/// reads. Opening the experiment, pasting a link, or receiving an App Clip payload does not grant
/// permission to commit.
public struct InvocationContext: Hashable, Sendable {
    /// How the host obtained the URL string.
    public enum Source: String, Hashable, Sendable, Codable, CaseIterable {
        /// An original fixture the person chose in the experiment UI.
        case fixtureReplay
        /// Text the person pasted or typed.
        case pasted
        /// A URL the system delivered to the full app (`onOpenURL` / universal link).
        case openedURL
        /// An App Clip activation payload URL, when that target is configured.
        case appClip
    }

    /// Whether the host believes it can reach the network. Offline never blocks a local deep link
    /// or a fixture replay; it only changes how an https universal-link style invocation falls back.
    public enum Reachability: String, Hashable, Sendable, Codable, CaseIterable {
        case online
        case offline
    }

    public let source: Source
    public let rawURL: String
    public let reachability: Reachability
    public let receivedAt: Date

    public init(
        source: Source,
        rawURL: String,
        reachability: Reachability = .online,
        receivedAt: Date = Date()
    ) {
        self.source = source
        self.rawURL = rawURL
        self.reachability = reachability
        self.receivedAt = receivedAt
    }
}

/// How a validated proposal reached the doorway after parsing.
public enum InvocationChannel: String, Hashable, Sendable, Codable, CaseIterable {
    /// `https://doorway.nativelab.example/...` — the universal-link shape. Needs associated domains
    /// and hosting to invoke an App Clip or open the app from Safari; the core build validates the
    /// same shape from fixtures without hosting.
    case universalLink
    /// `nativelab://doorway/...` — the full-app deep link fallback. No public hosting.
    case deepLink
}
