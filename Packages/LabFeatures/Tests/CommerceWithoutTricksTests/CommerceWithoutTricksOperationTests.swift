import Foundation
import LabDomain
import Testing
@testable import CommerceWithoutTricks

@MainActor
@Suite struct CommerceWithoutTricksOperationTests {
    @Test func noPathCreatesARealCharge() async throws {
        let (desk, backend) = commerceLab()
        #expect(desk.createsRealCharge == false)
        #expect(CommerceWithoutTricks.createsRealCharge == false)
        let commit = try await desk.purchase(
            CommerceFixture.notebook.id,
            script: .verified,
            through: backend,
            requestID: RequestID()
        )
        guard case .committed(let receipt) = commit else {
            Issue.record("Expected a committed entitlement")
            return
        }
        #expect(receipt.admitted.adapter == .appUI)
        let encoded = try JSONEncoder().encode(receipt)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains("Simulated") || desk.entitlement(for: CommerceFixture.notebook.id)?.noteSummary.contains("no real charge") == true)
        #expect(desk.entitlement(for: CommerceFixture.notebook.id)?.noteSummary.contains("no real charge") == true)
    }

    @Test func anUnverifiedTransactionGrantsNothing() async throws {
        let (desk, backend) = commerceLab()
        let commit = try await desk.purchase(
            CommerceFixture.notebook.id,
            script: .unverified,
            through: backend,
            requestID: RequestID()
        )
        guard case .unchanged = commit else {
            Issue.record("Unverified must not write the store")
            return
        }
        #expect(desk.state(for: CommerceFixture.notebook.id) == .unverified)
        #expect(desk.entitlement(for: CommerceFixture.notebook.id) == nil)
        #expect(try await backend.item(CommerceFixture.notebook.itemID) == nil)
        #expect(desk.currentEntitlements().isEmpty)
        // VerificationResult.makeEntitlement refuses unverified.
        let tx = SimulatedTransaction(
            id: "x",
            productID: CommerceFixture.notebook.id,
            verification: .unverified(reason: "bad"),
            purchasedAt: .now
        )
        #expect(tx.verification.makeEntitlement(
            product: CommerceFixture.notebook,
            transactionID: tx.id,
            source: .purchase
        ) == nil)
    }

    @Test func restoreDoesNotNeedAPrivateDeveloperAccount() async throws {
        let (desk, backend) = commerceLab()
        _ = try await desk.purchase(
            CommerceFixture.notebook.id,
            script: .verified,
            through: backend,
            requestID: RequestID()
        )
        _ = try await desk.purchase(
            CommerceFixture.compass.id,
            script: .verified,
            through: backend,
            requestID: RequestID()
        )
        let receipts = try await desk.restore(through: backend, requestID: RequestID())
        #expect(receipts.count >= 1)
        #expect(desk.state(for: CommerceFixture.notebook.id) == .restored)
        #expect(desk.entitlement(for: CommerceFixture.notebook.id)?.source == .restore)
        #expect(desk.entitlement(for: CommerceFixture.compass.id)?.source == .restore)
        // No Apple Account or developer credential appears in any entitlement note.
        for entitlement in desk.currentEntitlements() {
            #expect(!entitlement.noteSummary.lowercased().contains("apple id"))
            #expect(!entitlement.noteSummary.lowercased().contains("developer"))
            #expect(entitlement.noteSummary.contains("no real charge"))
        }
    }

    @Test func theLocalSimulatorCoversBuyRestoreRefundPendingAndOffline() async throws {
        let (desk, backend) = commerceLab()
        // Buy
        _ = try await desk.purchase(
            CommerceFixture.notebook.id,
            script: .verified,
            through: backend,
            requestID: RequestID()
        )
        #expect(desk.state(for: CommerceFixture.notebook.id) == .purchased)
        #expect(desk.entitlement(for: CommerceFixture.notebook.id) != nil)

        // Pending approval grants nothing until approved
        _ = try await desk.purchase(
            CommerceFixture.compass.id,
            script: .pendingApproval,
            through: backend,
            requestID: RequestID()
        )
        #expect(desk.state(for: CommerceFixture.compass.id) == .pendingApproval)
        #expect(desk.entitlement(for: CommerceFixture.compass.id) == nil)
        #expect(try await backend.item(CommerceFixture.compass.itemID) == nil)
        _ = try await desk.approvePending(
            CommerceFixture.compass.id,
            through: backend,
            requestID: RequestID()
        )
        #expect(desk.entitlement(for: CommerceFixture.compass.id) != nil)

        // Offline keeps prior entitlements readable; new purchase fails
        desk.setOffline(true)
        #expect(desk.isOffline)
        #expect(desk.state(for: CommerceFixture.notebook.id) == .offline)
        #expect(desk.entitlement(for: CommerceFixture.notebook.id) != nil)
        await #expect(throws: CommerceError.offlineUnavailable) {
            try await desk.purchase(
                CommerceFixture.notebook.id,
                script: .verified,
                through: backend,
                requestID: RequestID()
            )
        }
        desk.setOffline(false)

        // Restore
        _ = try await desk.restore(through: backend, requestID: RequestID())
        #expect(desk.state(for: CommerceFixture.notebook.id) == .restored)

        // Refund
        _ = try await desk.refund(
            CommerceFixture.notebook.id,
            through: backend,
            requestID: RequestID()
        )
        #expect(desk.state(for: CommerceFixture.notebook.id) == .refunded)
        #expect(desk.entitlement(for: CommerceFixture.notebook.id) == nil)
        let refunded = try #require(await backend.item(CommerceFixture.notebook.itemID))
        #expect(refunded.note.value.contains("Refunded"))

        // Revoke the other product
        _ = try await desk.revoke(
            CommerceFixture.compass.id,
            through: backend,
            requestID: RequestID()
        )
        #expect(desk.state(for: CommerceFixture.compass.id) == .revoked)
        #expect(desk.entitlement(for: CommerceFixture.compass.id) == nil)
    }

    @Test func sensitiveOperationsShareTheDomainReceiptPath() async throws {
        let (desk, backend) = commerceLab()
        let commit = try await desk.purchase(
            CommerceFixture.notebook.id,
            script: .verified,
            through: backend,
            requestID: RequestID()
        )
        guard case .committed(let receipt) = commit else {
            Issue.record("Expected a receipt")
            return
        }
        #expect(receipt.status == .committed)
        #expect(receipt.admitted.adapter == .appUI)
        if case .createItem(let draft) = receipt.admitted.operation {
            #expect(draft.id == CommerceFixture.notebook.itemID)
            #expect(draft.collectionID == CommerceFixture.collection)
        } else {
            Issue.record("Expected createItem through OperationService")
        }
        let item = try #require(await backend.item(CommerceFixture.notebook.itemID))
        #expect(item.note.value.contains("Entitled"))
        #expect(item.note.value.contains("no real charge"))

        let refund = try await desk.refund(
            CommerceFixture.notebook.id,
            through: backend,
            requestID: RequestID()
        )
        guard case .committed(let refundReceipt) = refund else {
            Issue.record("Expected a refund receipt")
            return
        }
        #expect(refundReceipt.admitted.adapter == .appUI)
        if case .updateItem(let id, _, _) = refundReceipt.admitted.operation {
            #expect(id == CommerceFixture.notebook.itemID)
        } else {
            Issue.record("Expected updateItem for refund")
        }
    }

    @Test func productsPresentTruthfulNamesAndTerms() {
        let desk = CommerceDesk()
        #expect(desk.products.count == 2)
        for product in desk.products {
            #expect(!product.displayName.isEmpty)
            #expect(product.terms.contains("No real charge"))
            #expect(product.terms.contains("Simulated"))
            #expect(product.displayPrice.contains("simulated"))
            #expect(product.id.rawValue.hasPrefix("lab.commerce."))
        }
        #expect(CommerceFixture.notebook.displayName == "Field Notebook Unlock")
        #expect(CommerceFixture.compass.displayName == "Sample Compass Overlay")
    }

    @Test func cancellationAndUnavailablePathsChangeNothing() async throws {
        let desk = CommerceDesk()
        await #expect(throws: CommerceError.cancelled) {
            try await desk.purchase(
                CommerceFixture.notebook.id,
                script: .verified,
                through: CancelledBackend(),
                requestID: RequestID()
            )
        }
        #expect(desk.entitlement(for: CommerceFixture.notebook.id) == nil)
        #expect(desk.state(for: CommerceFixture.notebook.id) == .available)
        #expect(try await desk.restore(through: ServiceBackend(service: OperationService(store: InMemoryOperationStore())), requestID: RequestID()).isEmpty)
        let (fresh, backend) = commerceLab()
        let cancelled = try await fresh.purchase(
            CommerceFixture.notebook.id,
            script: .cancelled,
            through: backend,
            requestID: RequestID()
        )
        guard case .unchanged = cancelled else {
            Issue.record("Cancelled purchase must not write")
            return
        }
        #expect(try await backend.item(CommerceFixture.notebook.itemID) == nil)
        #expect(fresh.entitlement(for: CommerceFixture.notebook.id) == nil)

        await #expect(throws: CommerceError.labUnavailable("The store did not open.")) {
            try await CommerceDesk().purchase(
                CommerceFixture.notebook.id,
                script: .verified,
                through: UnavailableBackend(),
                requestID: RequestID()
            )
        }
    }

    @Test func invalidProductAndEmptyPendingAreRefused() async throws {
        let (desk, backend) = commerceLab()
        await #expect(throws: CommerceError.unknownProduct) {
            try await desk.purchase(
                ProductID(rawValue: "lab.commerce.missing"),
                script: .verified,
                through: backend,
                requestID: RequestID()
            )
        }
        await #expect(throws: CommerceError.nothingPending) {
            try await desk.approvePending(
                CommerceFixture.notebook.id,
                through: backend,
                requestID: RequestID()
            )
        }
        await #expect(throws: CommerceError.nothingToRefund) {
            try await desk.refund(
                CommerceFixture.notebook.id,
                through: backend,
                requestID: RequestID()
            )
        }
        #expect(try await backend.item(CommerceFixture.notebook.itemID) == nil)
    }

    @Test func resetClearsOnlyCommerceState() async throws {
        let (desk, backend) = commerceLab()
        _ = try await desk.purchase(
            CommerceFixture.notebook.id,
            script: .verified,
            through: backend,
            requestID: RequestID()
        )
        let receipts = try await desk.reset(through: backend, requestID: RequestID())
        #expect(!receipts.isEmpty)
        #expect(desk.entitlement(for: CommerceFixture.notebook.id) == nil)
        #expect(desk.state(for: CommerceFixture.notebook.id) == .available)
        let item = try #require(await backend.item(CommerceFixture.notebook.itemID))
        #expect(item.note.value.contains("Not entitled"))
        #expect(try await backend.collection(CommerceFixture.collection) != nil)
    }
}

