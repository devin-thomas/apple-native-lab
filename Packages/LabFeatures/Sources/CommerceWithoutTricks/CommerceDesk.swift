import Foundation
import LabDomain

/// The commerce desk: local product fixtures, a transaction-state simulator, and
/// entitlement writes through `CommerceBackend`.
///
/// Every sensitive grant (purchase, restore, approve, refund, revoke) that changes an entitlement
/// commits as `createItem` or `updateItem` through the operation service. An unverified
/// transaction never reaches that path.
@MainActor
public final class CommerceDesk {
    private var simulator: TransactionStateSimulator

    public init(simulator: TransactionStateSimulator = TransactionStateSimulator()) {
        self.simulator = simulator
    }

    public var products: [CommerceProduct] { CommerceFixture.products }
    public var isOffline: Bool { simulator.isOffline }
    public var createsRealCharge: Bool { CommerceWithoutTricks.createsRealCharge }

    public func state(for productID: ProductID) -> PurchaseState {
        simulator.state(for: productID)
    }

    public func entitlement(for productID: ProductID) -> VerifiedEntitlement? {
        simulator.entitlement(for: productID)
    }

    public func currentEntitlements() -> [VerifiedEntitlement] {
        simulator.currentEntitlements()
    }

    public func setOffline(_ value: Bool) {
        guard !running else { return }
        simulator.setOffline(value)
    }

    private enum Action: Hashable {
        case purchase(ProductID, SimulatedPurchaseScript)
        case approve(ProductID)
        case refund(ProductID)
        case revoke(ProductID)
        case restore
        case reset
    }

    private var running = false
    private var requests: [RequestID: (Action, [ActionReceipt])] = [:]

    @discardableResult
    public func purchase(_ productID: ProductID, script: SimulatedPurchaseScript,
                         through backend: any CommerceBackend, requestID: RequestID) async throws(CommerceError) -> CommerceCommit {
        let receipts = try await run(.purchase(productID, script), through: backend, requestID: requestID) { (staged: TransactionStateSimulator) async throws(CommerceError) -> [ActionReceipt] in
            let before = staged.entitlement(for: productID)
            _ = try staged.purchase(productID, script: script)
            guard let after = staged.entitlement(for: productID), after != before else { return [] }
            return try await self.persistReceipts(after, through: backend, requestID: requestID)
        }
        return receipts.first.map(CommerceCommit.committed) ?? .unchanged
    }

    @discardableResult
    public func approvePending(_ productID: ProductID, through backend: any CommerceBackend,
                               requestID: RequestID) async throws(CommerceError) -> CommerceCommit {
        let receipts = try await run(.approve(productID), through: backend, requestID: requestID) { (staged: TransactionStateSimulator) async throws(CommerceError) -> [ActionReceipt] in
            let entitlement = try staged.approvePending(productID)
            return try await self.persistReceipts(entitlement, through: backend, requestID: requestID)
        }
        return receipts.first.map(CommerceCommit.committed) ?? .unchanged
    }

    @discardableResult
    public func refund(_ productID: ProductID, through backend: any CommerceBackend,
                       requestID: RequestID) async throws(CommerceError) -> CommerceCommit {
        let receipts = try await run(.refund(productID), through: backend, requestID: requestID) { (staged: TransactionStateSimulator) async throws(CommerceError) -> [ActionReceipt] in
            try staged.refund(productID)
            return try await self.clearReceipts(productID, state: .refunded, through: backend, requestID: requestID)
        }
        return receipts.first.map(CommerceCommit.committed) ?? .unchanged
    }

    @discardableResult
    public func revoke(_ productID: ProductID, through backend: any CommerceBackend,
                       requestID: RequestID) async throws(CommerceError) -> CommerceCommit {
        let receipts = try await run(.revoke(productID), through: backend, requestID: requestID) { (staged: TransactionStateSimulator) async throws(CommerceError) -> [ActionReceipt] in
            try staged.revoke(productID)
            return try await self.clearReceipts(productID, state: .revoked, through: backend, requestID: requestID)
        }
        return receipts.first.map(CommerceCommit.committed) ?? .unchanged
    }

    /// Restore is a sequence of product commits. Successful earlier products remain committed if
    /// a later product fails; retrying uses the same per-product requests.
    @discardableResult
    public func restore(through backend: any CommerceBackend, requestID: RequestID) async throws(CommerceError) -> [ActionReceipt] {
        try await run(.restore, through: backend, requestID: requestID) { (staged: TransactionStateSimulator) async throws(CommerceError) -> [ActionReceipt] in
            let restored = try staged.restore()
            var receipts: [ActionReceipt] = []
            for entitlement in restored {
                receipts += try await self.persistReceipts(entitlement, through: backend,
                                                          requestID: self.productRequest(requestID, entitlement.productID))
                self.simulator.adopt(entitlement.productID, from: staged)
            }
            return receipts
        }
    }

    @discardableResult
    public func reset(through backend: any CommerceBackend, requestID: RequestID) async throws(CommerceError) -> [ActionReceipt] {
        try await run(.reset, through: backend, requestID: requestID) { (staged: TransactionStateSimulator) async throws(CommerceError) -> [ActionReceipt] in
            var receipts: [ActionReceipt] = []
            for product in CommerceFixture.products {
                guard let item = try await backend.item(product.itemID) else { continue }
                guard item.collectionID == CommerceFixture.collection else { throw .stateChanged }
                let note = try self.itemNote(self.availableNote(for: product))
                guard item.note != note else { continue }
                let receipt = try await performChecked(through: backend,
                    .updateItem(id: item.id, expected: item.revision, changes: self.itemChanges(note: note)),
                    requestID: self.productRequest(requestID, product.id), names: self.names(for: product))
                try self.requireCommit(receipt)
                receipts.append(receipt)
                let cleared = staged.copy()
                cleared.reset()
                self.simulator.adopt(product.id, from: cleared)
            }
            staged.reset()
            return receipts
        }
    }

    /// Simulator changes stay private until the backend accepts the operation. Actor ownership
    /// and the running guard prevent an async suspension from admitting another desk mutation.
    private func run(_ action: Action, through backend: any CommerceBackend, requestID: RequestID,
                     body: (TransactionStateSimulator) async throws(CommerceError) -> [ActionReceipt]) async throws(CommerceError) -> [ActionReceipt] {
        try cancelled()
        guard !running else { throw .operationInProgress }
        running = true
        defer { running = false }
        if let (previous, receipts) = requests[requestID] {
            guard previous == action else { throw .operation(.requestIDReused(requestID)) }
            // Replays must pass the service's current authorization again (ADR-011).
            for receipt in receipts {
                _ = try await performChecked(through: backend, receipt.admitted.operation, requestID: receipt.requestID, names: [:])
            }
            return receipts
        }
        guard requests.count < 256 else { throw .sessionLimit }
        let staged = simulator.copy()
        let receipts = try await body(staged)
        simulator = staged
        requests[requestID] = (action, receipts)
        return receipts
    }

    private func productRequest(_ requestID: RequestID, _ productID: ProductID) -> RequestID {
        var bytes = requestID.rawValue.uuid
        if productID == CommerceFixture.compass.id { bytes.15 ^= 1 }
        return RequestID(rawValue: UUID(uuid: bytes))
    }

    private func performChecked(through backend: any CommerceBackend, _ operation: DomainOperation,
                                requestID: RequestID, names: [EntityReference: String]) async throws(CommerceError) -> ActionReceipt {
        try cancelled()
        let receipt = try await backend.perform(operation, requestID: requestID, names: names)
        try requireCommit(receipt)
        return receipt
    }

    private func requireCommit(_ receipt: ActionReceipt) throws(CommerceError) {
        if case .conflict = receipt.status { throw .stateChanged }
    }

    private func persistReceipts(_ entitlement: VerifiedEntitlement, through backend: any CommerceBackend,
                                 requestID: RequestID) async throws(CommerceError) -> [ActionReceipt] {
        switch try await persist(entitlement, through: backend, requestID: requestID) {
        case .unchanged: return []
        case .committed(let receipt):
            try requireCommit(receipt)
            return [receipt]
        }
    }

    private func clearReceipts(_ productID: ProductID, state: PurchaseState, through backend: any CommerceBackend,
                               requestID: RequestID) async throws(CommerceError) -> [ActionReceipt] {
        switch try await clearEntitlementNote(productID, state: state, through: backend, requestID: requestID) {
        case .unchanged: return []
        case .committed(let receipt):
            try requireCommit(receipt)
            return [receipt]
        }
    }

    // MARK: Persistence

    private func persist(
        _ entitlement: VerifiedEntitlement,
        through backend: any CommerceBackend,
        requestID: RequestID
    ) async throws(CommerceError) -> CommerceCommit {
        guard let product = CommerceFixture.product(id: entitlement.productID) else {
            throw .unknownProduct
        }
        try await ensureCollection(through: backend)
        let note = try itemNote(entitlement.noteSummary)
        let title = try validatedTitle(product.displayName)
        if let item = try await backend.item(product.itemID) {
            guard item.collectionID == CommerceFixture.collection else { throw .stateChanged }
            if item.note == note { return .unchanged }
            let update = try itemChanges(note: note)
            let receipt = try await performChecked(through: backend,
                .updateItem(id: item.id, expected: item.revision, changes: update),
                requestID: requestID,
                names: names(for: product)
            )
            return .committed(receipt)
        }
        let receipt = try await performChecked(through: backend,
            .createItem(draft: ItemDraft(
                id: product.itemID,
                in: CommerceFixture.collection,
                title: title,
                note: note
            )),
            requestID: requestID,
            names: names(for: product)
        )
        return .committed(receipt)
    }

    private func clearEntitlementNote(
        _ productID: ProductID,
        state: PurchaseState,
        through backend: any CommerceBackend,
        requestID: RequestID
    ) async throws(CommerceError) -> CommerceCommit {
        guard let product = CommerceFixture.product(id: productID) else { throw .unknownProduct }
        guard let item = try await backend.item(product.itemID) else { return .unchanged }
        guard item.collectionID == CommerceFixture.collection else { throw .stateChanged }
        let cleared = try itemNote(clearedNote(for: product, state: state))
        if item.note == cleared { return .unchanged }
        let update = try itemChanges(note: cleared)
        let receipt = try await performChecked(through: backend,
            .updateItem(id: item.id, expected: item.revision, changes: update),
            requestID: requestID,
            names: names(for: product)
        )
        return .committed(receipt)
    }

    private func ensureCollection(through backend: any CommerceBackend) async throws(CommerceError) {
        if try await backend.collection(CommerceFixture.collection) != nil { return }
        let title = try validatedTitle(CommerceFixture.collectionTitle)
        let receipt = try await performChecked(through: backend,
            .createCollection(draft: CollectionDraft(id: CommerceFixture.collection, title: title)),
            requestID: CommerceFixture.createCollectionRequest,
            names: [.collection(CommerceFixture.collection): title.value]
        )
        try requireCommit(receipt)
    }

    private func availableNote(for product: CommerceProduct) -> String {
        "Not entitled. \(product.displayName) is available in the local product fixtures. Simulated; no real charge."
    }

    private func clearedNote(for product: CommerceProduct, state: PurchaseState) -> String {
        "\(state.title). \(product.displayName) is not entitled. Simulated; no real charge."
    }

    private func cancelled() throws(CommerceError) {
        if Task.isCancelled { throw .cancelled }
    }

    private func validatedTitle(_ raw: String) throws(CommerceError) -> EntityTitle {
        do { return try EntityTitle(raw) } catch { throw .operation(.invalidPayload(error)) }
    }

    private func itemNote(_ raw: String) throws(CommerceError) -> ItemNote {
        do { return try ItemNote(raw) } catch { throw .operation(.invalidPayload(error)) }
    }

    private func itemChanges(note: ItemNote) throws(CommerceError) -> ItemChanges {
        do { return try ItemChanges(title: nil, note: note) } catch { throw .operation(.invalidPayload(error)) }
    }

    private func names(for product: CommerceProduct) -> [EntityReference: String] {
        [
            .item(product.itemID): product.displayName,
            .collection(CommerceFixture.collection): CommerceFixture.collectionTitle,
        ]
    }
}
