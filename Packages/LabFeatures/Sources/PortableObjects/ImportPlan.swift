import CryptoKit
import Foundation
import LabDomain

/// What importing one document would do to the lab, decided before anything is written.
///
/// Identity decides, never a title: the document's `documentID` is the item ID. An object the lab
/// does not hold becomes a new item with that ID. An object it holds is never duplicated: with the
/// same title and note there is nothing to do, and with different ones the person may apply the
/// document's title and note to the stored item at the revision the review saw, as one update
/// with a receipt and an undo. Nothing is overwritten without that choice.
public enum ImportPlan: Hashable, Sendable {
    /// A new item with the document's stable ID, in the collection the person chooses.
    case create(ItemContent)
    /// The lab holds this object with the same title and note. Importing it again changes nothing.
    case alreadyPresent(stored: LabItem)
    /// The lab holds this object with a different title or note. Applying updates the stored item
    /// at `stored.revision`; its extras stay as stored.
    case differs(stored: LabItem, content: ItemContent, changes: ItemChanges)
    /// The document is valid but cannot be imported, for the reason given.
    case refused(PortableObjectError, stored: LabItem?)

    public var stored: LabItem? {
        switch self {
        case .create: nil
        case .alreadyPresent(let stored), .differs(let stored, _, _): stored
        case .refused(_, let stored): stored
        }
    }

    /// Whether committing this plan would change the lab.
    public var commits: Bool {
        switch self {
        case .create, .differs: true
        case .alreadyPresent, .refused: false
        }
    }

    /// Plans the import of `document` against the lab as `backend` reads it now.
    static func plan(_ document: LabDocument, backend: any PortableObjectsBackend) async throws(PortableObjectError) -> ImportPlan {
        let stored = try await backend.item(document.itemID)
        guard document.attachments.isEmpty else {
            return .refused(.attachmentsNotSupported(count: document.attachments.count), stored: stored)
        }
        let content: ItemContent
        do {
            content = try DocumentMapping.itemContent(of: document)
        } catch {
            return .refused(error, stored: stored)
        }
        guard let stored else { return .create(content) }
        let newTitle = stored.title == content.title ? nil : content.title
        let newNote = stored.note == content.note ? nil : content.note
        guard newTitle != nil || newNote != nil else { return .alreadyPresent(stored: stored) }
        guard !stored.isArchived else { return .refused(.storedCopyArchived, stored: stored) }
        do {
            return .differs(stored: stored, content: content, changes: try ItemChanges(title: newTitle, note: newNote))
        } catch {
            return .alreadyPresent(stored: stored)
        }
    }

    /// Whether two plans commit the same change, so a commit may use the one it reviewed.
    func sameDecision(as other: ImportPlan) -> Bool {
        switch (self, other) {
        case (.create(let a), .create(let b)): a == b
        case (.differs(let a, _, let changesA), .differs(let b, _, let changesB)):
            a.id == b.id && a.revision == b.revision && changesA == changesB
        default: false
        }
    }
}

/// One staged document, validated and planned, waiting for the person to decide.
public struct ImportReview: Hashable, Sendable, Identifiable {
    /// The staged import. Its bytes stay in staging until the commit or a discard.
    public let id: StagingID
    public let document: LabDocument
    /// SHA-256 of the canonical document: what the commit checks it is committing.
    public let digest: ContentDigest
    public let plan: ImportPlan
    /// The staged size in bytes.
    public let byteCount: Int

    /// Changes the item would make to the document, as sentences.
    public var adjustments: [String] {
        switch plan {
        case .create(let content), .differs(_, let content, _): content.adjustments
        case .alreadyPresent, .refused: []
        }
    }
}

/// A committed import.
public struct ImportResult: Hashable, Sendable {
    public enum Change: Hashable, Sendable {
        /// A new item with the document's stable ID.
        case created
        /// The stored item took the document's title and note.
        case updated
    }

    public let receipt: ActionReceipt
    public let change: Change
    /// The item after the commit, when it could be read.
    public let item: LabItem?
    /// `true` when this request had already committed, so its recorded receipt was returned and
    /// nothing new was written.
    public let isReplay: Bool
}

/// The request IDs imports use. Each derives from the document's canonical digest and what the
/// commit targets, so a retry of the same decision replays its receipt instead of committing again.
enum ImportRequest {
    static func create(_ digest: ContentDigest, into collection: CollectionID) -> RequestID {
        RequestID(rawValue: derived("create", digest, collection.rawValue.uuidString))
    }

    static func update(_ digest: ContentDigest, item: ItemID, at revision: Revision) -> RequestID {
        RequestID(rawValue: derived("update", digest, "\(item.rawValue.uuidString)/\(revision.rawValue)"))
    }

    /// A version-8 UUID from SHA-256 over a label, the digest, and a target.
    private static func derived(_ label: String, _ digest: ContentDigest, _ target: String) -> UUID {
        var hasher = SHA256()
        hasher.update(data: Array("native-lab/portable-objects/\(label)/".utf8))
        hasher.update(data: digest.bytes)
        hasher.update(data: Array("/\(target)".utf8))
        var raw = Array(hasher.finalize().prefix(16))
        raw[6] = (raw[6] & 0x0F) | 0x80
        raw[8] = (raw[8] & 0x3F) | 0x80
        return UUID(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
        ))
    }
}
