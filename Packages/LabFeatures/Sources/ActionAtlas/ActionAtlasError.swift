import Foundation
import LabDomain

/// Why an Action Atlas action did not complete. Every case changed nothing, and each has a
/// sentence a person can act on, which Shortcuts and the in-app browser both show.
public enum ActionAtlasError: Error, Hashable, Sendable {
    /// The app's store cannot be used right now.
    case unavailable(reason: String)
    case invalidInput(ValidationError)
    /// A request ID supplied by a shortcut is not a UUID.
    case invalidRequestID
    case missingItem(ItemID)
    case missingCollection(CollectionID)
    /// A new item needs one of the person's own collections, and there is none yet.
    case noCollectionOfYourOwn
    /// Several of the person's collections could take the new item, and none was chosen.
    case ambiguousCollection(candidates: Int)
    /// A new item cannot go into a demo collection (ADR-012).
    case demoCollection
    /// The entity changed after it was picked. The conflict receipt is recorded; nothing moved.
    case conflict(RevisionConflict)
    /// The operation service refused the request for another reason.
    case refused(OperationError)
    /// The action was cancelled before anything was committed.
    case cancelled

    /// Maps a service refusal to the most specific case.
    public init(_ error: OperationError) {
        switch error {
        case .invalidPayload(let validation): self = .invalidInput(validation)
        case .notFound(.item(let id)): self = .missingItem(id)
        case .notFound(.collection(let id)): self = .missingCollection(id)
        case .ruleViolation(.demoCollection): self = .demoCollection
        default: self = .refused(error)
        }
    }

    /// One or two plain sentences: what happened and what to do. Never a path, SQL, or content
    /// beyond what the person typed.
    public var message: String {
        switch self {
        case .unavailable(let reason):
            reason
        case .invalidInput(let validation):
            Self.describe(validation)
        case .invalidRequestID:
            "The request ID must be a UUID, such as one made by the Shortcuts action “UUID”. Nothing was changed."
        case .missingItem:
            "That lab item no longer exists. Find it again, then retry. Nothing was changed."
        case .missingCollection:
            "That collection no longer exists. Choose another collection. Nothing was changed."
        case .noCollectionOfYourOwn:
            "You have no collection of your own yet. Create a collection first; demo collections hold only the samples."
        case .ambiguousCollection(let candidates):
            "\(candidates) of your collections could hold the item. Choose one. Nothing was changed."
        case .demoCollection:
            "Demo collections hold only the samples. Choose one of your own collections, or create one. Nothing was changed."
        case .conflict(let conflict):
            "Not applied: the \(conflict.entity.kind.rawValue) changed after it was picked (expected revision \(conflict.expected), found \(conflict.current)). Get it again and retry. Its receipt is in Native Lab."
        case .refused(let error):
            Self.describe(error)
        case .cancelled:
            "Cancelled. Nothing was changed."
        }
    }

    private static func describe(_ validation: ValidationError) -> String {
        switch validation {
        case .emptyTitle: "A title cannot be empty. Nothing was changed."
        case .titleTooLong(let limit): "A title can have at most \(limit) characters. Nothing was changed."
        case .noteTooLong(let limit): "A note can have at most \(limit) characters. Nothing was changed."
        case .searchTextTooLong(let limit): "Search text can have at most \(limit) characters."
        case .controlCharacter(let field): "The \(field.rawValue) contains a control character, which is not allowed. Nothing was changed."
        case .emptyChanges: "Give a new title, a new note, or both. Nothing was changed."
        case .resultLimitOutOfRange(let allowed): "The result limit must be between \(allowed.lowerBound) and \(allowed.upperBound)."
        case .unsupportedSchemaVersion: "This request uses a format this build does not read. Nothing was changed."
        }
    }

    private static func describe(_ error: OperationError) -> String {
        switch error {
        case .invalidPayload(let validation):
            describe(validation)
        case .unauthorized(let denial) where denial.required == .commitDestructive && denial.adapter == .appIntent:
            "Archiving from Shortcuts or Siri needs your confirmation, and none was given. Nothing was changed."
        case .unauthorized(let denial) where denial.required == .commitDestructive:
            "This change needs your explicit approval in Native Lab. Nothing was changed."
        case .unauthorized:
            "Native Lab does not allow this action from here. Nothing was changed."
        case .notFound(let entity):
            "That \(entity.kind.rawValue) no longer exists. Nothing was changed."
        case .requestIDReused:
            "That request ID was already used for a different change. Use a new request ID. Nothing was changed."
        case .ruleViolation(let violation):
            describe(violation)
        case .storeFailure(.readFailed):
            "Reading the lab store failed. Try again."
        case .storeFailure(.commitFailed):
            "The change was not saved. Nothing was written. Try again."
        case .storeFailure(.contention):
            "Other changes kept interfering, so nothing was written. Try again."
        }
    }

    private static func describe(_ violation: RuleViolation) -> String {
        switch violation {
        case .alreadyExists: "It already exists. Nothing was changed."
        case .alreadyArchived: "It is already archived. Nothing was changed."
        case .notArchived: "It is not archived, so there is nothing to restore."
        case .archived: "It is archived. Restore it before changing it."
        case .collectionArchived: "That collection is archived. Restore it or choose another. Nothing was changed."
        case .demoCollection: "Demo collections hold only the samples. Choose one of your own collections. Nothing was changed."
        case .noChanges: "Nothing would change: the new values match the current ones."
        }
    }
}

extension ActionAtlasError: LocalizedError, CustomLocalizedStringResourceConvertible {
    public var errorDescription: String? { message }

    public var localizedStringResource: LocalizedStringResource { "\(message)" }
}
