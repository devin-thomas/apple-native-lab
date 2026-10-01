import Foundation
import LabDomain

/// Where an attention request arrived. The host maps it to an adapter kind (ADR-011).
public enum AttentionEntryPoint: String, Hashable, Sendable {
    case appUI = "app-ui"
    case appIntent = "app-intent"

    public var adapter: AdapterKind {
        switch self {
        case .appUI: .appUI
        case .appIntent: .appIntent
        }
    }
}

/// Proof that a person confirmed this exact operation. The intent creates one only after its
/// dialog returns. It is not `Codable`.
public struct AttentionConfirmation: Hashable, Sendable {
    public let operation: DomainOperation

    public init(confirmed operation: DomainOperation) {
        self.operation = operation
    }

    public func covers(_ operation: DomainOperation) -> Bool { self.operation == operation }
}

public protocol AttentionBackend: Sendable {
    func attentions(via entryPoint: AttentionEntryPoint) async throws(AttentionError) -> [LabAttention]

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        via entryPoint: AttentionEntryPoint,
        confirmation: AttentionConfirmation?
    ) async throws(AttentionError) -> ActionReceipt
}

public enum AttentionError: Error, Hashable, Sendable {
    case invalid(ValidationError)
    case refused(OperationError)
    case unavailable(String)
    case cancelled

    public var message: String {
        switch self {
        case .invalid(.consentRequired):
            "Scheduling a lab alert needs a separate confirmation. Nothing was scheduled."
        case .invalid:
            "That alert is not valid. Nothing was scheduled."
        case .refused(.unauthorized):
            "This entry point is not allowed to change lab alerts. Nothing was changed."
        case .refused(.ruleViolation(.nothingToCancel)):
            "There are no lab alerts to cancel."
        case .refused:
            "The lab alert could not be changed. Nothing was changed."
        case .unavailable(let reason):
            reason
        case .cancelled:
            "Cancelled. Nothing was changed."
        }
    }
}

public enum AttentionOutcome: Hashable, Sendable {
    case scheduled(ActionReceipt, LabAttention)
    case cancelled(ActionReceipt)
    case restored(ActionReceipt)

    public var receipt: ActionReceipt {
        switch self {
        case .scheduled(let receipt, _), .cancelled(let receipt), .restored(let receipt): receipt
        }
    }
}

/// Scheduling, cancelling, and reading lab alerts. The page and the intents both use this.
///
/// Every change is one domain operation through the backend, so it is authorized and recorded.
/// A preview is not a change. A cancelled task commits nothing.
public struct AttentionActions: Sendable {
    public let backend: any AttentionBackend
    public let entryPoint: AttentionEntryPoint

    public init(backend: any AttentionBackend, entryPoint: AttentionEntryPoint) {
        self.backend = backend
        self.entryPoint = entryPoint
    }

    public func attentions() async throws(AttentionError) -> [LabAttention] {
        try cancelled()
        return try await backend.attentions(via: entryPoint)
    }

    public func schedule(
        _ offer: AttentionOffer,
        consent: AttentionConsent,
        requestID: RequestID = RequestID(),
        confirmation: AttentionConfirmation? = nil
    ) async throws(AttentionError) -> AttentionOutcome {
        try cancelled()
        let draft: AttentionDraft
        do { draft = try offer.draft(consent: consent) } catch let error { throw .invalid(error) }
        let current = try await backend.attentions(via: entryPoint)
        try cancelled()
        let expected = current.first { $0.id == draft.id }?.revision
        let operation = DomainOperation.scheduleAttention(expected: expected, draft: draft)
        let receipt = try await backend.commit(operation, requestID: requestID, via: entryPoint, confirmation: confirmation)
        guard receipt.conflict == nil else { return .scheduled(receipt, LabAttention(draft, revision: expected ?? .initial)) }
        let stored = try await backend.attentions(via: entryPoint).first { $0.id == draft.id }
        return .scheduled(receipt, stored ?? LabAttention(draft))
    }

    /// Cancels every stored lab alert. Identifiers that were never stored are not named.
    public func cancelAll(
        requestID: RequestID = RequestID(),
        confirmation: AttentionConfirmation? = nil
    ) async throws(AttentionError) -> AttentionOutcome {
        try cancelled()
        let current = try await backend.attentions(via: entryPoint)
        let pins = current.map { AttentionPin(id: $0.id, expected: $0.revision) }
        let operation = DomainOperation.cancelLabAlerts(pins: pins)
        let receipt = try await backend.commit(operation, requestID: requestID, via: entryPoint, confirmation: confirmation)
        return .cancelled(receipt)
    }

    /// Commits an operation the caller already built, such as the one an intent just confirmed.
    public func commit(
        _ operation: DomainOperation,
        requestID: RequestID = RequestID(),
        confirmation: AttentionConfirmation? = nil
    ) async throws(AttentionError) -> AttentionOutcome {
        try cancelled()
        let receipt = try await backend.commit(operation, requestID: requestID, via: entryPoint, confirmation: confirmation)
        switch operation {
        case .cancelLabAlerts: return .cancelled(receipt)
        case .restoreLabAlerts: return .restored(receipt)
        case .scheduleAttention(_, let draft): return .scheduled(receipt, LabAttention(draft))
        default: return .cancelled(receipt)
        }
    }
}

private func cancelled() throws(AttentionError) {
    if Task.isCancelled { throw .cancelled }
}

/// The handle App Intents receive. Until the host registers one, intents refuse.
public final class RespectfulAttentionLink: Sendable {
    public let backend: any AttentionBackend

    public init(backend: any AttentionBackend) {
        self.backend = backend
    }

    public func actions(_ entryPoint: AttentionEntryPoint) -> AttentionActions {
        AttentionActions(backend: backend, entryPoint: entryPoint)
    }

    public static let unavailable = RespectfulAttentionLink(
        backend: UnavailableAttentionBackend(
            reason: "Native Lab has not opened its store yet. Open Native Lab and try again."
        )
    )
}

public struct UnavailableAttentionBackend: AttentionBackend {
    public let reason: String

    public init(reason: String) { self.reason = reason }

    public func attentions(via entryPoint: AttentionEntryPoint) async throws(AttentionError) -> [LabAttention] {
        throw .unavailable(reason)
    }

    public func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        via entryPoint: AttentionEntryPoint,
        confirmation: AttentionConfirmation?
    ) async throws(AttentionError) -> ActionReceipt {
        throw .unavailable(reason)
    }
}
