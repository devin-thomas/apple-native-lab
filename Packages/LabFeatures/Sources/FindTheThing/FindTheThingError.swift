import Foundation
import LabDomain

/// Why a Find the Thing operation did not change the index, or could not finish an archive.
public enum FindTheThingError: Error, Hashable, Sendable {
    case cancelled
    /// The store that would archive a lab item is not open. The index was not changed.
    case unavailable(reason: String)
    /// The adapter's ceiling or the actor's grants, using the domain's denial reasons.
    case unauthorized(adapter: AdapterKind, required: Permission, reason: AuthorizationDenial.Reason)
    /// The lab item was already archived. The index may still drop the record.
    case alreadyArchived
    /// The lab item is already gone. The index may still drop the record.
    case missingItem
    case refused(OperationError)

    public init(_ error: OperationError) {
        switch error {
        case .ruleViolation(.alreadyArchived(_)):
            self = .alreadyArchived
        case .notFound:
            self = .missingItem
        case .unauthorized(let denial):
            self = .unauthorized(adapter: denial.adapter, required: denial.required, reason: denial.reason)
        default:
            self = .refused(error)
        }
    }

    public var message: String {
        switch self {
        case .cancelled:
            "Cancelled. The index was not changed."
        case .unavailable(let reason):
            reason
        case .unauthorized(_, _, .outsideAdapterCeiling):
            "This action is not available from here. Nothing was changed."
        case .unauthorized:
            "This change needs your explicit approval in Native Lab. Nothing was changed."
        case .alreadyArchived:
            "That record is already archived."
        case .missingItem:
            "That record is no longer in the lab."
        case .refused:
            "The lab could not archive that record. It is still in the index."
        }
    }
}
