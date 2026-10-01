import Foundation

/// How a verified entitlement was obtained. Restore and offline reuse never invent a new charge.
public enum EntitlementSource: String, Hashable, Sendable, Codable {
    case purchase
    case restore
    case offlineCache
}

/// An entitlement that passed verification. There is no public way to build one from an
/// unverified transaction: only `TransactionVerification.makeEntitlement` produces one.
public struct VerifiedEntitlement: Hashable, Sendable {
    public let productID: ProductID
    public let transactionID: String
    public let displayName: String
    public let terms: String
    public let source: EntitlementSource
    public let grantedAt: Date

    /// A one-line summary for the lab item note and the receipt inspector. It holds no secret.
    public var noteSummary: String {
        "Entitled: \(displayName) (\(productID.rawValue)). Source: \(source.rawValue). Transaction \(transactionID). Simulated; no real charge."
    }
}

/// The outcome of verifying a simulated transaction, mirroring StoreKit 2's
/// `VerificationResult` (`.verified` / `.unverified`) without linking StoreKit.
public enum TransactionVerification: Hashable, Sendable {
    case verified
    case unverified(reason: String)

    /// Builds a `VerifiedEntitlement` only for `.verified`. Unverified returns `nil`.
    public func makeEntitlement(
        product: CommerceProduct,
        transactionID: String,
        source: EntitlementSource,
        grantedAt: Date = .now
    ) -> VerifiedEntitlement? {
        guard case .verified = self else { return nil }
        return VerifiedEntitlement(
            productID: product.id,
            transactionID: transactionID,
            displayName: product.displayName,
            terms: product.terms,
            source: source,
            grantedAt: grantedAt
        )
    }
}

/// One simulated transaction. It is not an App Store transaction and never creates a charge.
public struct SimulatedTransaction: Hashable, Sendable {
    public let id: String
    public let productID: ProductID
    public let verification: TransactionVerification
    public let purchasedAt: Date
}
