import Foundation
import LabDomain

/// What Wallet Moment needs from the host: commits through the host's own `OperationService`, as
/// the app UI. Wallet Moment never holds the store.
public protocol WalletMomentBackend: Sendable {
    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(WalletMomentError) -> ActionReceipt
}

/// A backend over an `OperationService`, for tests and fixture replays. The host uses its library
/// instead so receipts reach its receipt views.
public struct ServiceWalletBackend: WalletMomentBackend {
    private let service: OperationService
    private let actor: ActorScope

    public init(service: OperationService, actor: ActorScope) {
        self.service = service
        self.actor = actor
    }

    public func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(WalletMomentError) -> ActionReceipt {
        _ = names
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw WalletMomentError(error)
        }
    }
}

extension WalletMomentError {
    public init(_ error: OperationError) {
        switch error {
        case .unauthorized: self = .notAuthorized
        case .notFound, .ruleViolation(.collectionArchived), .ruleViolation(.demoCollection):
            self = .destinationUnavailable
        case .ruleViolation(.alreadyExists), .ruleViolation(.noChanges): self = .stateChanged
        case .ruleViolation, .requestIDReused: self = .identifierConflict
        case .invalidPayload: self = .stateChanged
        case .storeFailure: self = .storeUnavailable
        }
    }
}
