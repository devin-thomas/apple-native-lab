import Foundation
import LabDomain

/// Why the desk refused an action. A refusal changes nothing.
public enum TrustDeskError: Error, Hashable, Sendable {
    case noLiveGrant
    case grantExpired
    case grantRevoked
    case lifetimeOutOfRange
    case invalidDisplayName(ValidationError)
    case displayNameUnchanged
    case passkeyNotRegistered
    case passkeyIsNotAnAppSecret
    case secretStoreUnavailable(String)
    case labUnavailable(String)
    case cancelled
    case operation(OperationError)

    public var message: String {
        switch self {
        case .noLiveGrant:
            "A live local authorization is required to open the sealed record. Nothing was changed."
        case .grantExpired:
            "The local authorization expired. Nothing was changed. Authorize again to continue."
        case .grantRevoked:
            "The local authorization was revoked. Nothing was changed."
        case .lifetimeOutOfRange:
            "A grant must last more than zero and at most 300 seconds."
        case .invalidDisplayName(let error):
            switch error {
            case .emptyTitle: "The display name is empty. The identity was not changed."
            case .titleTooLong(let limit): "The display name is longer than \(limit) characters. The identity was not changed."
            case .controlCharacter: "The display name contains a control character. The identity was not changed."
            default: "The display name is not usable. The identity was not changed."
            }
        case .displayNameUnchanged:
            "The display name is already that. The identity was not changed."
        case .passkeyNotRegistered:
            "There is no simulated passkey for this identity yet. Nothing was changed."
        case .passkeyIsNotAnAppSecret:
            "A passkey is not an app secret, and this simulation cannot export one."
        case .secretStoreUnavailable(let reason):
            "The keychain is unavailable (\(reason)). Nothing was changed."
        case .labUnavailable(let reason):
            "The lab is unavailable (\(reason)). Nothing was changed."
        case .cancelled:
            "The action was cancelled. Nothing was changed."
        case .operation:
            "The lab refused the change. Nothing else was changed."
        }
    }
}
