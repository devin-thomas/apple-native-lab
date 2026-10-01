import Foundation
import LabDomain

/// Why a ledger operation stopped. A refusal writes nothing new into the lab store. The
/// explanation is what the interface shows; it never includes a path, an account token, or a payload
/// from another account.
public enum LedgerError: Error, Hashable, Sendable {
    case unauthorized
    case cancelled
    case icloudDisabled
    case notAShareMember
    case wrongAccount
    case foreignLedger
    case unresolvedConflict(RecordID)
    case invalidDocument(String)
    case invalidMutation(String)
    case domain(String)
    case storage

    public var explanation: String {
        switch self {
        case .unauthorized:
            "That change was not authorized, so the ledger was not changed."
        case .cancelled:
            "The change was cancelled, so the ledger was not changed."
        case .icloudDisabled:
            "iCloud is off for this profile. The local ledger is unchanged. Export a document to move edits by hand."
        case .notAShareMember:
            "This account is not a member of the shared database, so nothing was read or written."
        case .wrongAccount:
            "This document belongs to another account, so it was not applied."
        case .foreignLedger:
            "This ledger belongs to another account or device, so it was not opened."
        case .unresolvedConflict:
            "This record has edits that were made apart. Choose one before editing it again."
        case .invalidDocument(let reason), .invalidMutation(let reason), .domain(let reason):
            reason
        case .storage:
            "The ledger could not be saved. Nothing new was committed."
        }
    }

    static func describe(_ error: ValidationError) -> String {
        switch error {
        case .emptyTitle: "The title is empty."
        case .titleTooLong: "The title is too long."
        case .noteTooLong: "The note is too long."
        case .controlCharacter: "The title or note contains a control character."
        default: "The edit is not valid."
        }
    }
}
