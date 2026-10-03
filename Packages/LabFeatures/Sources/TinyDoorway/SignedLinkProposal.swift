import Foundation
import LabDomain

/// What a validated doorway link may ask for. Only `.visit` exists; a link never selects an
/// arbitrary `DomainOperation`.
public enum DoorwayActionKind: String, Hashable, Sendable, Codable, CaseIterable {
    case visit
}

/// A sealed proposal built only by `DoorwayValidator` after domain, path, and parameter checks.
///
/// It is "signed" in the lab sense: a `ContentDigest` seal over the canonical fields, not an Apple
/// App Clip code signature. Nothing untrusted can construct one; there is no public initializer and
/// no decoder. Confirming it still requires a separate person action that goes through
/// `OperationService` with a receipt. The proposal itself never becomes a grant.
public struct SignedLinkProposal: Hashable, Sendable {
    public let action: DoorwayActionKind
    public let itemID: ItemID
    public let channel: InvocationChannel
    /// Canonical URL string the seal covers (scheme, host, path, sorted query).
    public let canonicalURL: String
    public let seal: ContentDigest
    public let context: InvocationContext

    /// Builds a proposal only after the validator has checked every field. Not public.
    init(
        action: DoorwayActionKind,
        itemID: ItemID,
        channel: InvocationChannel,
        canonicalURL: String,
        context: InvocationContext
    ) {
        self.action = action
        self.itemID = itemID
        self.channel = channel
        self.canonicalURL = canonicalURL
        self.context = context
        self.seal = ContentDigest.sha256(Data("\(action.rawValue)|\(itemID.rawValue.uuidString.lowercased())|\(channel.rawValue)|\(canonicalURL)".utf8))
    }

    /// One sentence for the review UI.
    public func reviewSentence(itemTitle: String) -> String {
        "Open a visit to “\(itemTitle)” and, if you confirm, append the visit marker to its note."
    }
}

/// Outcome of validating an invocation: a sealed visit proposal, the local information page, or a
/// refusal.
public enum DoorwayValidation: Hashable, Sendable {
    case proposal(SignedLinkProposal)
    /// The local information page. No operation; no network.
    case informationPage(InvocationChannel)
    case refused(DoorwayError)
}
