import LabDomain

/// Why commerce refused an action. A refusal changes nothing in the store.
public enum CommerceError: Error, Hashable, Sendable {
    case operationInProgress
    case stateChanged
    case sessionLimit
    case unknownProduct
    case unverifiedTransaction
    case nothingPending
    case nothingToRefund
    case nothingToRevoke
    case offlineUnavailable
    case labUnavailable(String)
    case cancelled
    case operation(OperationError)

    public var message: String {
        switch self {
        case .operationInProgress:
            "Another commerce action is still running."
        case .stateChanged:
            "The record changed before the action committed. Review it before trying again."
        case .sessionLimit:
            "This simulator session has reached its action limit. Open a new session."
        case .unknownProduct:
            "That product is not in the local product fixtures. Nothing was changed."
        case .unverifiedTransaction:
            "The transaction was not verified, so nothing was entitled. Nothing was changed."
        case .nothingPending:
            "There is no purchase waiting for approval. Nothing was changed."
        case .nothingToRefund:
            "There is no entitled purchase to refund. Nothing was changed."
        case .nothingToRevoke:
            "There is no entitled purchase to revoke. Nothing was changed."
        case .offlineUnavailable:
            "The simulator is offline. A new purchase or restore cannot run. Previously verified entitlements stay readable."
        case .labUnavailable(let reason):
            "The lab is unavailable (\(reason)). Nothing was changed."
        case .cancelled:
            "The action was cancelled. Nothing was changed."
        case .operation:
            "The lab refused the change. Nothing else was changed."
        }
    }
}
