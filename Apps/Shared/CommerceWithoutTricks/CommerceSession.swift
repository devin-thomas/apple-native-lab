import CommerceWithoutTricks
import LabDomain
import Observation
import SwiftUI

/// LAB-040's names in the catalog and the sidebar.
enum CommerceExperiment {
    static let id = CommerceWithoutTricks.experimentID
    static let title = CommerceWithoutTricks.title
    static let symbol = CommerceWithoutTricks.symbol
}

/// One screen's commerce desk. Every entitlement grant commits through `LabLibrary.submit`, the
/// same app-UI path as the rest of the lab. Purchase buttons only drive the local simulator.
@MainActor
@Observable
final class CommerceSession {
    private let desk: CommerceDesk
    private(set) var message: String?
    private(set) var receipt: ReceiptRecord?
    private(set) var isRunning = false
    /// Which purchase script the Buy button uses. Defaults to a verified simulated purchase.
    var purchaseScript: SimulatedPurchaseScript = .verified
    var selectedProductID: ProductID = CommerceFixture.notebook.id

    @ObservationIgnored private var purchaseRequest: RequestID?
    @ObservationIgnored private var restoreRequest: RequestID?
    @ObservationIgnored private var resetRequest: RequestID?

    init(desk: CommerceDesk = CommerceDesk()) {
        self.desk = desk
    }

    var products: [CommerceProduct] { desk.products }
    var isOffline: Bool { desk.isOffline }
    var chargeBoundary: String { CommerceWithoutTricks.chargeBoundaryLabel }

    func state(for productID: ProductID) -> PurchaseState { desk.state(for: productID) }
    func entitlement(for productID: ProductID) -> VerifiedEntitlement? { desk.entitlement(for: productID) }

    func purchase(in library: LabLibrary) async -> ReceiptRecord? {
        guard begin() else { return nil }
        defer { isRunning = false }
        let requestID = purchaseRequest ?? RequestID()
        purchaseRequest = requestID
        do {
            switch try await desk.purchase(
                selectedProductID,
                script: purchaseScript,
                through: LibraryCommerceBackend(library: library),
                requestID: requestID
            ) {
            case .committed(let receipt):
                purchaseRequest = nil
                let sentence: String
                switch purchaseScript {
                case .verified:
                    sentence = "Simulated purchase verified. Entitlement recorded. No real charge."
                default:
                    sentence = "Purchase settled through the lab. No real charge."
                }
                return finish(receipt, in: library, sentence: sentence)
            case .unchanged:
                purchaseRequest = nil
                message = unchangedMessage(for: purchaseScript)
                LabAnnouncement(text: message ?? "").post()
                return nil
            }
        } catch {
            let sentence = describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
            return nil
        }
    }

    func approvePending(in library: LabLibrary) async -> ReceiptRecord? {
        guard begin() else { return nil }
        defer { isRunning = false }
        let requestID = RequestID()
        do {
            switch try await desk.approvePending(
                selectedProductID,
                through: LibraryCommerceBackend(library: library),
                requestID: requestID
            ) {
            case .committed(let receipt):
                return finish(receipt, in: library, sentence: "Pending purchase approved. Entitlement recorded. No real charge.")
            case .unchanged:
                message = "Nothing to approve."
                return nil
            }
        } catch {
            let sentence = describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
            return nil
        }
    }

    func restore(in library: LabLibrary) async -> ReceiptRecord? {
        guard begin() else { return nil }
        defer { isRunning = false }
        let requestID = restoreRequest ?? RequestID()
        restoreRequest = requestID
        do {
            let receipts = try await desk.restore(
                through: LibraryCommerceBackend(library: library),
                requestID: requestID
            )
            restoreRequest = nil
            guard let last = receipts.last else {
                message = desk.currentEntitlements().isEmpty
                    ? "No entitled products are in this session’s history."
                    : "Simulated entitlements are already restored."
                LabAnnouncement(text: message ?? "").post()
                return nil
            }
            return finish(last, in: library, sentence: "Restored from local transaction history. No Apple Account was used. No real charge.")
        } catch {
            let sentence = describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
            return nil
        }
    }

    func refund(in library: LabLibrary) async -> ReceiptRecord? {
        guard begin() else { return nil }
        defer { isRunning = false }
        do {
            switch try await desk.refund(
                selectedProductID,
                through: LibraryCommerceBackend(library: library),
                requestID: RequestID()
            ) {
            case .committed(let receipt):
                return finish(receipt, in: library, sentence: "Refund recorded locally. Entitlement cleared. No real charge.")
            case .unchanged:
                message = "Nothing to refund."
                return nil
            }
        } catch {
            let sentence = describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
            return nil
        }
    }

    func revoke(in library: LabLibrary) async -> ReceiptRecord? {
        guard begin() else { return nil }
        defer { isRunning = false }
        do {
            switch try await desk.revoke(
                selectedProductID,
                through: LibraryCommerceBackend(library: library),
                requestID: RequestID()
            ) {
            case .committed(let receipt):
                return finish(receipt, in: library, sentence: "Revocation recorded locally. Entitlement cleared. No real charge.")
            case .unchanged:
                message = "Nothing to revoke."
                return nil
            }
        } catch {
            let sentence = describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
            return nil
        }
    }

    func setOffline(_ value: Bool) {
        desk.setOffline(value)
        message = value
            ? "Simulator offline. Previously verified entitlements stay readable. New purchases and restores are refused."
            : "Simulator online again."
        LabAnnouncement(text: message ?? "").post()
    }

    func reset(in library: LabLibrary) async -> ReceiptRecord? {
        guard begin() else { return nil }
        defer { isRunning = false }
        let requestID = resetRequest ?? RequestID()
        resetRequest = requestID
        do {
            let receipts = try await desk.reset(
                through: LibraryCommerceBackend(library: library),
                requestID: requestID
            )
            resetRequest = nil
            message = "Reset the commerce desk. Other lab records were kept."
            LabAnnouncement(text: message ?? "").post()
            guard let last = receipts.last else { return nil }
            return finish(last, in: library, sentence: message ?? "")
        } catch {
            let sentence = describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
            return nil
        }
    }

    private func unchangedMessage(for script: SimulatedPurchaseScript) -> String {
        switch script {
        case .verified:
            "Nothing changed."
        case .unverified:
            "Unverified transaction. It granted no entitlement. No real charge."
        case .pendingApproval:
            "Purchase is pending approval. It has granted no new entitlement. No real charge."
        case .cancelled:
            "Purchase cancelled. Nothing was changed. No real charge."
        case .failed:
            "Purchase failed. Nothing was changed. No real charge."
        }
    }

    private func begin() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    private func finish(_ receipt: ActionReceipt, in library: LabLibrary, sentence: String) -> ReceiptRecord {
        let product = CommerceFixture.product(id: selectedProductID)
        let record = ReceiptRecord(
            receipt: receipt,
            recordedAt: .now,
            names: [
                .item(product?.itemID ?? CommerceFixture.notebook.itemID): product?.displayName ?? CommerceFixture.notebook.displayName,
                .collection(CommerceFixture.collection): CommerceFixture.collectionTitle,
            ]
        )
        let listed = library.receipt(id: receipt.operationID) ?? record
        self.receipt = listed
        message = sentence
        LabAnnouncement(text: sentence).post()
        return listed
    }

    private func describe(_ error: any Error) -> String {
        guard let error = error as? CommerceError else { return LibraryMessages.describe(error) }
        if case .operation(let operation) = error { return LibraryMessages.describe(operation) }
        return error.message
    }
}

/// The host's operation service, as the app UI. Commerce never holds the store.
struct LibraryCommerceBackend: CommerceBackend {
    let library: LabLibrary

    func item(_ id: ItemID) async throws(CommerceError) -> LabItem? {
        let service = try await opened()
        do { return try await service.item(id, as: LabDataService.appUI) } catch .notFound {
            return nil
        } catch {
            throw .operation(error)
        }
    }

    func collection(_ id: CollectionID) async throws(CommerceError) -> LabCollection? {
        let service = try await opened()
        do { return try await service.collection(id, as: LabDataService.appUI) } catch .notFound {
            return nil
        } catch {
            throw .operation(error)
        }
    }

    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(CommerceError) -> ActionReceipt {
        do {
            return try await library.submit(operation, requestID: requestID, authority: .userAction, names: names).receipt
        } catch let failure as LabLibrary.SubmitFailure {
            switch failure {
            case .unavailable(let reason): throw .labUnavailable(reason)
            case .refused(let error): throw .operation(error)
            }
        } catch {
            throw .labUnavailable("The lab could not commit the change.")
        }
    }

    private func opened() async throws(CommerceError) -> LabDataService {
        do { return try await library.openedService() } catch let failure as LabLibrary.SubmitFailure {
            switch failure {
            case .unavailable(let reason): throw .labUnavailable(reason)
            case .refused(let error): throw .operation(error)
            }
        } catch {
            throw .labUnavailable("The lab store is still opening. Try again.")
        }
    }
}
