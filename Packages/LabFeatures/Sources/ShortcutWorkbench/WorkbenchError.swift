import Foundation
import LabDomain

/// Why a workbench action did not complete. Every case changed nothing (or discarded a cancelled
/// import), and each has a sentence a person can act on.
public enum WorkbenchError: Error, Hashable, Sendable {
    case unavailable(reason: String)
    case invalidInput(String)
    case invalidRequestID
    case missingRecipe(RecipeID)
    case missingItem(ItemID)
    case conflict(RevisionConflict)
    case refused(OperationError)
    case cancelled
    case importIncomplete(reason: String)

    public init(_ error: OperationError) {
        switch error {
        case .notFound(.item(let id)): self = .missingItem(id)
        default: self = .refused(error)
        }
    }

    public var message: String {
        switch self {
        case .unavailable(let reason):
            reason
        case .invalidInput(let detail):
            "\(detail) Nothing was changed."
        case .invalidRequestID:
            "The request ID must be a UUID, such as one made by the Shortcuts action “UUID”. Nothing was changed."
        case .missingRecipe:
            "That recipe is not in this workbench. Choose another recipe. Nothing was changed."
        case .missingItem:
            "That lab item no longer exists. Find it again, then retry. Nothing was changed."
        case .conflict(let conflict):
            "Not applied: the \(conflict.entity.kind.rawValue) changed after it was picked (expected revision \(conflict.expected), found \(conflict.current)). Get it again and retry. Its receipt is in Native Lab."
        case .refused(let error):
            Self.describe(error)
        case .cancelled:
            "Cancelled. Nothing was kept from this import, and nothing was changed."
        case .importIncomplete(let reason):
            "\(reason) Nothing was imported."
        }
    }

    private static func describe(_ error: OperationError) -> String {
        switch error {
        case .unauthorized(let denial) where denial.required == .commitDestructive:
            "This change needs your explicit approval in Native Lab. Nothing was changed."
        case .unauthorized:
            "Native Lab does not allow this action from here. Nothing was changed."
        case .notFound(let entity):
            "That \(entity.kind.rawValue) no longer exists. Nothing was changed."
        case .requestIDReused:
            "That request ID was already used for a different change. Use a new request ID. Nothing was changed."
        case .invalidPayload:
            "The change was refused because its values were not valid. Nothing was changed."
        case .ruleViolation(.noChanges):
            "Nothing would change: the new values match the current ones."
        case .ruleViolation:
            "The lab refused this change. Nothing was written."
        case .storeFailure(.readFailed):
            "Reading the lab store failed. Try again."
        case .storeFailure(.commitFailed):
            "The change was not saved. Nothing was written. Try again."
        case .storeFailure(.contention):
            "Other changes kept interfering, so nothing was written. Try again."
        }
    }
}

extension WorkbenchError: LocalizedError, CustomLocalizedStringResourceConvertible {
    public var errorDescription: String? { message }
    public var localizedStringResource: LocalizedStringResource { "\(message)" }
}
