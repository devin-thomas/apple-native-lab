import Foundation

/// Why a doorway link was refused or could not run. Nothing is committed in any of these cases.
public enum DoorwayError: Error, Hashable, Sendable {
    /// The string is not a URL the doorway can read.
    case malformedLink
    /// The scheme is not `https` or the local `nativelab` deep link.
    case unsupportedScheme(String)
    /// The host is not the lab's doorway host.
    case untrustedHost(String)
    /// The path is not an allowed doorway path.
    case unknownPath(String)
    /// The path asks for a privileged or unknown action.
    case privilegedAction(String)
    /// A query key is not on the allowlist (or looks like an operation/grant).
    case untrustedParameter(String)
    /// A visit link is missing its `item` parameter, or the value is not a UUID.
    case missingItem
    /// The link carries userinfo credentials.
    case linkContainsCredentials
    /// Network is offline and this channel needs reachability; the local fallback is explained.
    case offline(fallback: String)
    /// The App Clip path is not configured in this build.
    case clipUnavailable(String)
    /// The proposal's demo sample is missing, archived, or not demo data.
    case itemUnavailable(String)
    /// The sample already carries the visit marker; confirming again would change nothing.
    case alreadyVisited(String)
    /// The caller cancelled before a commit.
    case cancelled

    public var message: String {
        switch self {
        case .malformedLink:
            "That link is not a valid doorway URL. Nothing was opened."
        case .unsupportedScheme(let scheme):
            "The “\(scheme)” scheme is not accepted. Use an https doorway link or a nativelab deep link."
        case .untrustedHost(let host):
            "“\(host)” is not the lab's doorway host. Nothing was opened."
        case .unknownPath(let path):
            "The path “\(path)” is not a doorway action. Nothing was opened."
        case .privilegedAction(let name):
            "“\(name)” is not a doorway action and cannot run from a link. Nothing was changed."
        case .untrustedParameter(let name):
            "The parameter “\(name)” is not allowed on a doorway link. Nothing was opened."
        case .missingItem:
            "A visit link must name one demo sample with item=<uuid>. Nothing was opened."
        case .linkContainsCredentials:
            "Doorway links must not carry credentials. Nothing was opened."
        case .offline(let fallback):
            fallback
        case .clipUnavailable(let reason):
            reason
        case .itemUnavailable(let title):
            "“\(title)” is not an available demo sample for this visit. Nothing was changed."
        case .alreadyVisited(let title):
            "“\(title)” already records this visit. Nothing was changed."
        case .cancelled:
            "The visit was cancelled. Nothing was changed."
        }
    }
}
