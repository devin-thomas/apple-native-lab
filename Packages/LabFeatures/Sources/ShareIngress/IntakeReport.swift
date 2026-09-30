import Foundation
import LabDomain

/// What happened to one attachment of an intake.
public enum AttachmentResult: Hashable, Sendable {
    /// Staged for review under this ID.
    case staged(StagingID)
    /// The same content was already waiting under this ID. Nothing new was stored.
    case duplicate(StagingID)
    /// Refused. Nothing from this attachment was kept, and the next one was still tried.
    case refused(ImportRejection)
    /// The intake was cancelled before or while this attachment was read.
    case cancelled
}

public struct AttachmentOutcome: Hashable, Sendable, Identifiable {
    /// 1-based, in the order the source listed its attachments.
    public let position: Int
    public let contentType: String?
    public let result: AttachmentResult

    public var id: Int { position }

    /// A sentence for the person, naming the position and never the content.
    public var message: String {
        switch result {
        case .staged: "Item \(position) is waiting for review."
        case .duplicate: "Item \(position) was already waiting for review."
        case .refused(let rejection): "Item \(position): \(rejection.userMessage)"
        case .cancelled: "Item \(position) was not imported: the import was cancelled."
        }
    }
}

/// The result of one intake, in order.
public struct IntakeReport: Hashable, Sendable {
    public let batch: BatchID
    public let surface: IngressSurface
    public let source: InboxSource
    /// Why the whole intake was refused before any attachment was read, if it was.
    public let refusal: ImportRejection?
    /// One outcome per attachment, in the source's order. Empty when the intake was refused whole.
    public let outcomes: [AttachmentOutcome]
    /// The person cancelled. Anything this intake had staged was removed again.
    public let wasCancelled: Bool

    public var stagedCount: Int { outcomes.count { if case .staged = $0.result { true } else { false } } }
    public var duplicateCount: Int { outcomes.count { if case .duplicate = $0.result { true } else { false } } }
    public var refusedCount: Int { outcomes.count { if case .refused = $0.result { true } else { false } } }

    /// The staging IDs now waiting because of this intake, new or already there, in order.
    public var waitingIDs: [StagingID] {
        outcomes.compactMap {
            switch $0.result {
            case .staged(let id), .duplicate(let id): id
            case .refused, .cancelled: nil
            }
        }
    }

    /// One sentence summarizing the intake. It names counts, never content.
    public var summary: String {
        if let refusal { return "Nothing was imported. \(refusal.userMessage)" }
        if wasCancelled { return "The import was cancelled. Nothing from it was kept." }
        var parts: [String] = []
        if stagedCount > 0 { parts.append(stagedCount == 1 ? "1 item is waiting for review" : "\(stagedCount) items are waiting for review") }
        if duplicateCount > 0 { parts.append(duplicateCount == 1 ? "1 was already waiting" : "\(duplicateCount) were already waiting") }
        if refusedCount > 0 { parts.append(refusedCount == 1 ? "1 was refused" : "\(refusedCount) were refused") }
        guard !parts.isEmpty else { return "Nothing was imported." }
        return parts.joined(separator: ", ").prefix(1).uppercased() + parts.joined(separator: ", ").dropFirst() + "."
    }
}
