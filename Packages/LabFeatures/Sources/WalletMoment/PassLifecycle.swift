import Foundation

/// Where a pass sits in its lifetime, judged against a clock the caller supplies.
///
/// Expiration is honest: once `now` is at or after `expiresAt`, the state is `.expired` even if
/// the barcode still scans. Upcoming and active are distinct so a preview can say so plainly.
public enum PassLifecycleState: String, Hashable, Sendable, CaseIterable {
    case upcoming
    case active
    case expired

    public var title: String {
        switch self {
        case .upcoming: "Upcoming"
        case .active: "Active"
        case .expired: "Expired"
        }
    }

    /// One sentence for the preview and the event card.
    public var sentence: String {
        switch self {
        case .upcoming: "This pass is not valid yet."
        case .active: "This pass is valid now."
        case .expired: "This pass has expired."
        }
    }
}

public enum PassLifecycle {
    /// The lifecycle of `definition` at `now`. Equality at the boundaries: before `startsAt` is
    /// upcoming, from `startsAt` until but not including `expiresAt` is active, and from
    /// `expiresAt` onward is expired.
    public static func state(of definition: PassDefinition, at now: Date) -> PassLifecycleState {
        if now < definition.startsAt { return .upcoming }
        if now < definition.expiresAt { return .active }
        return .expired
    }
}

/// An unsigned preview of a pass: the fields a person can inspect without any signing material.
///
/// Building a preview never calls a signer. The signing boundary is a separate, explicit action.
public struct PassPreview: Hashable, Sendable {
    public let definition: PassDefinition
    public let lifecycle: PassLifecycleState
    /// Always false for a preview built here: signing is outside this type.
    public let isSigned: Bool
    public let signingNote: String

    public init(definition: PassDefinition, at now: Date = Date()) {
        self.definition = definition
        self.lifecycle = PassLifecycle.state(of: definition, at: now)
        self.isSigned = false
        self.signingNote = "Unsigned preview. No pass-signing key is used to show this card."
    }

    public var headline: String { definition.eventName }
    public var detailLine: String {
        "\(definition.venue) · Seat \(definition.seat) · \(lifecycle.title)"
    }
}
