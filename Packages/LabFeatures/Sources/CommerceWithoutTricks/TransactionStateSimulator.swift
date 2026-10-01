import Foundation

/// How a simulated purchase should resolve. Tests and the UI pick an outcome explicitly so every
/// path is deterministic. None of these contact the App Store.
public enum SimulatedPurchaseScript: Hashable, Sendable {
    /// A verified purchase that may grant an entitlement.
    case verified
    /// A transaction that fails verification and grants nothing.
    case unverified
    /// Ask-to-Buy style: waits for an explicit approval before any entitlement.
    case pendingApproval
    case cancelled
    case failed
}

/// The declared fallback: a local transaction-state machine over the fixture products.
///
/// It records purchases, restores, refunds, revocations, and offline mode in memory. Restoration
/// reads that history; it never asks for an Apple Account or a private developer account.
@MainActor
public final class TransactionStateSimulator {
    private struct Record: Sendable {
        var state: PurchaseState
        var transaction: SimulatedTransaction?
        var entitlement: VerifiedEntitlement?
        var history: [SimulatedTransaction]
    }

    private var records: [ProductID: Record] = [:]
    private var offline = false
    private var sequence = 0
    private let sessionID: UUID

    func copy() -> TransactionStateSimulator {
        let copy = TransactionStateSimulator(sessionID: sessionID)
        copy.records = records
        copy.offline = offline
        copy.sequence = sequence
        return copy
    }

    func adopt(_ productID: ProductID, from staged: TransactionStateSimulator) {
        records[productID] = staged.records[productID]
    }

    private func withRecords<Value>(_ body: (inout [ProductID: Record]) -> Value) -> Value {
        body(&records)
    }

    public init(sessionID: UUID = UUID()) {
        self.sessionID = sessionID
        var initial: [ProductID: Record] = [:]
        for product in CommerceFixture.products {
            initial[product.id] = Record(state: .available, transaction: nil, entitlement: nil, history: [])
        }
        withRecords { $0 = initial }
    }

    public var isOffline: Bool { offline }

    public func state(for productID: ProductID) -> PurchaseState {
        withRecords { $0[productID]?.state ?? .available }
    }

    public func entitlement(for productID: ProductID) -> VerifiedEntitlement? {
        withRecords { $0[productID]?.entitlement }
    }

    public func transaction(for productID: ProductID) -> SimulatedTransaction? {
        withRecords { $0[productID]?.transaction }
    }

    /// Every product that currently holds a verified entitlement, including offline-cached ones.
    public func currentEntitlements() -> [VerifiedEntitlement] {
        withRecords { $0.values.compactMap(\.entitlement) }
            .sorted { $0.productID.rawValue < $1.productID.rawValue }
    }

    public func setOffline(_ value: Bool) {
        offline = value
        withRecords { records in
            for id in records.keys {
                guard var record = records[id] else { continue }
                if value {
                    if record.entitlement != nil {
                        record.state = .offline
                    }
                } else if record.state == .offline {
                    record.state = record.entitlement == nil ? .available : .purchased
                }
                records[id] = record
            }
        }
    }

    /// Runs one purchase script. Unverified, cancelled, failed, and pending paths leave
    /// entitlements unchanged. A verified purchase while offline fails closed.
    @discardableResult
    public func purchase(_ productID: ProductID, script: SimulatedPurchaseScript) throws(CommerceError) -> SimulatedTransaction? {
        guard let product = CommerceFixture.product(id: productID) else { throw .unknownProduct }
        if offline {
            withRecords { records in
                if var record = records[productID] {
                    record.state = record.entitlement == nil ? .failed : .offline
                    records[productID] = record
                }
            }
            throw .offlineUnavailable
        }
        switch script {
        case .cancelled:
            update(productID) { $0.state = .cancelled; $0.transaction = nil }
            return nil
        case .failed:
            update(productID) { $0.state = .failed; $0.transaction = nil }
            return nil
        case .pendingApproval:
            let tx = makeTransaction(productID: productID, verification: .verified)
            update(productID) {
                $0.state = .pendingApproval
                $0.transaction = tx
                // Pending must not grant yet, even though the transaction would verify.
                // A pending attempt must preserve an earlier verified entitlement.
            }
            return tx
        case .unverified:
            let tx = makeTransaction(
                productID: productID,
                verification: .unverified(reason: "Simulated signature failure")
            )
            update(productID) {
                $0.state = .unverified
                $0.transaction = tx
                $0.history.append(tx)
                // This transaction grants nothing. An earlier verified entitlement is kept.
            }
            return tx
        case .verified:
            let tx = makeTransaction(productID: productID, verification: .verified)
            let entitled = tx.verification.makeEntitlement(
                product: product,
                transactionID: tx.id,
                source: .purchase,
                grantedAt: tx.purchasedAt
            )
            update(productID) {
                $0.state = .purchased
                $0.transaction = tx
                $0.history.append(tx)
                $0.entitlement = entitled
            }
            return tx
        }
    }

    /// Approves a pending purchase. Without a pending transaction, nothing changes.
    @discardableResult
    public func approvePending(_ productID: ProductID) throws(CommerceError) -> VerifiedEntitlement {
        guard let product = CommerceFixture.product(id: productID) else { throw .unknownProduct }
        guard !offline else { throw .offlineUnavailable }
        let outcome: Result<VerifiedEntitlement, CommerceError> = withRecords { records in
            guard var record = records[productID] else { return .failure(.unknownProduct) }
            guard record.state == .pendingApproval, let tx = record.transaction else {
                return .failure(.nothingPending)
            }
            guard case .verified = tx.verification else { return .failure(.unverifiedTransaction) }
            guard let entitled = tx.verification.makeEntitlement(
                product: product,
                transactionID: tx.id,
                source: .purchase,
                grantedAt: tx.purchasedAt
            ) else {
                return .failure(.unverifiedTransaction)
            }
            record.state = .purchased
            record.entitlement = entitled
            record.history.append(tx)
            records[productID] = record
            return .success(entitled)
        }
        switch outcome {
        case .success(let entitled): return entitled
        case .failure(let error): throw error
        }
    }

    /// Restores from local history. No Apple Account and no private developer account are used.
    @discardableResult
    public func restore() throws(CommerceError) -> [VerifiedEntitlement] {
        if offline { throw .offlineUnavailable }
        return withRecords { records in
            var restored: [VerifiedEntitlement] = []
            for product in CommerceFixture.products {
                guard var record = records[product.id] else { continue }
                // Prefer the latest verified history entry that was not later refunded/revoked
                // in memory: a refunded/revoked product has no entitlement and an empty claim.
                if let entitled = record.entitlement {
                    let restoredEntitlement = VerifiedEntitlement(
                        productID: entitled.productID,
                        transactionID: entitled.transactionID,
                        displayName: entitled.displayName,
                        terms: entitled.terms,
                        source: .restore,
                        grantedAt: entitled.grantedAt
                    )
                    record.state = .restored
                    record.entitlement = restoredEntitlement
                    records[product.id] = record
                    restored.append(restoredEntitlement)
                    continue
                }
                if let lastVerified = record.history.last(where: {
                    if case .verified = $0.verification { return true }
                    return false
                }), record.state != .refunded, record.state != .revoked {
                    if let entitled = lastVerified.verification.makeEntitlement(
                        product: product,
                        transactionID: lastVerified.id,
                        source: .restore,
                        grantedAt: lastVerified.purchasedAt
                    ) {
                        record.entitlement = entitled
                        record.state = .restored
                        record.transaction = lastVerified
                        records[product.id] = record
                        restored.append(entitled)
                    }
                }
            }
            return restored
        }
    }

    public func refund(_ productID: ProductID) throws(CommerceError) {
        let outcome: Result<Void, CommerceError> = withRecords { records in
            guard var record = records[productID] else { return .failure(.unknownProduct) }
            guard record.entitlement != nil || record.state == .purchased || record.state == .restored || record.state == .offline else {
                return .failure(.nothingToRefund)
            }
            record.entitlement = nil
            record.history.removeAll()
            record.state = .refunded
            records[productID] = record
            return .success(())
        }
        if case .failure(let error) = outcome { throw error }
    }

    public func revoke(_ productID: ProductID) throws(CommerceError) {
        let outcome: Result<Void, CommerceError> = withRecords { records in
            guard var record = records[productID] else { return .failure(.unknownProduct) }
            guard record.entitlement != nil || record.state.mayHoldEntitlement else {
                return .failure(.nothingToRevoke)
            }
            record.entitlement = nil
            record.history.removeAll()
            record.state = .revoked
            records[productID] = record
            return .success(())
        }
        if case .failure(let error) = outcome { throw error }
    }

    /// Clears simulator state only. Store records are reset separately through the desk.
    public func reset() {
        offline = false
        sequence = 0
        withRecords { records in
            for id in records.keys {
                records[id] = Record(state: .available, transaction: nil, entitlement: nil, history: [])
            }
        }
    }

    private func makeTransaction(productID: ProductID, verification: TransactionVerification) -> SimulatedTransaction {
        sequence += 1
        let n = sequence
        return SimulatedTransaction(
            id: "sim-\(sessionID.uuidString)-tx-\(n)",
            productID: productID,
            verification: verification,
            purchasedAt: Date(timeIntervalSince1970: 1_725_000_000 + Double(n))
        )
    }

    private func update(_ productID: ProductID, _ body: (inout Record) -> Void) {
        withRecords { records in
            var record = records[productID] ?? Record(state: .available, transaction: nil, entitlement: nil, history: [])
            body(&record)
            records[productID] = record
        }
    }
}
