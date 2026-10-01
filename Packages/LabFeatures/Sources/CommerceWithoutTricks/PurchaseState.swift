/// Where one product stands in the local transaction-state simulator.
///
/// `unverified` means a transaction was produced but failed verification: it grants nothing.
/// `pendingApproval` is the Ask-to-Buy style path: nothing is entitled until approval.
/// `offline` means the network is unavailable; a previously verified entitlement remains readable.
public enum PurchaseState: String, Hashable, Sendable, CaseIterable {
    case available
    case purchasing
    case pendingApproval
    case purchased
    case restored
    case refunded
    case revoked
    case offline
    case cancelled
    case failed
    case unverified

    public var title: String {
        switch self {
        case .available: "Available"
        case .purchasing: "Purchasing"
        case .pendingApproval: "Pending approval"
        case .purchased: "Purchased"
        case .restored: "Restored"
        case .refunded: "Refunded"
        case .revoked: "Revoked"
        case .offline: "Offline"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        case .unverified: "Unverified"
        }
    }

    /// Whether this state may carry a `VerifiedEntitlement`. Unverified, pending, cancelled, and
    /// failed never do. Offline keeps a prior verified entitlement without a new purchase.
    public var mayHoldEntitlement: Bool {
        switch self {
        case .purchased, .restored, .offline: true
        case .available, .purchasing, .pendingApproval, .refunded, .revoked, .cancelled, .failed, .unverified:
            false
        }
    }
}
