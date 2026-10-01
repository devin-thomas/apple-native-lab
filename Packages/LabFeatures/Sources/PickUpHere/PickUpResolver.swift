import Foundation
import LabDomain

/// Whether this lab may show a draft. Revoked is decided before the item is read, so a refusal
/// never has the note in hand to reveal.
public enum DraftAccess: Hashable, Sendable {
    case permitted
    case revoked
}

/// What Pick Up Here needs from the host: authorized reads, and a commit only when a person
/// imports a document. The host implements it with the same library its views use.
public protocol PickUpBackend: Sendable {
    func access(to id: ItemID) async throws(PickUpError) -> DraftAccess
    /// The item, or `nil` when the lab has none. Not called when access is revoked.
    func item(_ id: ItemID) async throws(PickUpError) -> LabItem?
    func items() async throws(PickUpError) -> [LabItem]
    func collections() async throws(PickUpError) -> [LabCollection]
    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(PickUpError) -> ActionReceipt
}

/// A backend over an `OperationService`, as one actor. Tests use it; the host uses its library,
/// so an import's receipt joins the session's receipts. `revoked` is consulted before any read.
public struct ServicePickUpBackend: PickUpBackend {
    private let service: OperationService
    private let actor: ActorScope
    private let revoked: @Sendable (ItemID) -> Bool

    public init(
        service: OperationService,
        actor: ActorScope,
        revoked: @escaping @Sendable (ItemID) -> Bool = { _ in false }
    ) {
        self.service = service
        self.actor = actor
        self.revoked = revoked
    }

    public func access(to id: ItemID) async throws(PickUpError) -> DraftAccess {
        if revoked(id) { return .revoked }
        do {
            _ = try await service.findItem(id, as: actor)
            return .permitted
        } catch .unauthorized {
            return .revoked
        } catch .notFound {
            return .permitted
        } catch .storeFailure {
            throw .unavailable
        } catch {
            throw .unavailable
        }
    }

    public func item(_ id: ItemID) async throws(PickUpError) -> LabItem? {
        do {
            return try await service.findItem(id, as: actor)
        } catch .notFound {
            return nil
        } catch {
            throw PickUpError(error)
        }
    }

    public func items() async throws(PickUpError) -> [LabItem] {
        let filter: ItemFilter
        do {
            filter = try ItemFilter(includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
        } catch {
            throw .unavailable
        }
        do { return try await service.findItems(filter, as: actor) } catch { throw PickUpError(error) }
    }

    public func collections() async throws(PickUpError) -> [LabCollection] {
        let items = try await items()
        var collections: [LabCollection] = []
        for id in Set(items.map(\.collectionID)) {
            do {
                collections.append(try await service.findCollection(id, as: actor))
            } catch .notFound {
                continue
            } catch {
                throw PickUpError(error)
            }
        }
        return collections
    }

    public func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(PickUpError) -> ActionReceipt {
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw PickUpError(error)
        }
    }
}

extension PickUpError {
    public init(_ error: OperationError) {
        switch error {
        case .unauthorized: self = .notAuthorized
        case .notFound: self = .missing
        case .storeFailure: self = .unavailable
        case .ruleViolation(.demoCollection), .ruleViolation(.collectionArchived): self = .destinationUnavailable
        case .invalidPayload, .requestIDReused, .ruleViolation: self = .unavailable
        }
    }
}

/// What resuming a hint did. Only `.resumed` has the draft's words, and only after a permitted
/// read of the copy this device holds now.
public enum ResumeDecision: Hashable, Sendable {
    case resumed(ResumedDraft)
    /// The identifier is not in this lab. This is not an empty draft and not a success.
    case needsImport(DocumentLocator)
    /// Access was refused. The locator identifies the draft and carries none of its words.
    case accessRevoked(DocumentLocator)

    public var resumed: ResumedDraft? {
        if case .resumed(let draft) = self { draft } else { nil }
    }

    /// Text this decision is willing to show. A missing or revoked draft contributes nothing.
    public var revealedText: String {
        guard let resumed else { return "" }
        return ([resumed.title] + resumed.sections).joined(separator: "\n")
    }

    public var sentence: String {
        switch self {
        case .resumed(let draft):
            let place = "section \(draft.section + 1) of \(max(draft.sections.count, 1))"
            if draft.clamped, draft.newerRevision {
                return "This device has a newer copy. The saved section is gone, so the position moved to \(place)."
            }
            if draft.clamped {
                return "The saved position was past the end, so it moved to \(place)."
            }
            if draft.newerRevision {
                return "This device has a newer copy. Resumed at \(place). Its words may have changed."
            }
            return "Resumed at \(place)."
        case .needsImport:
            return "This draft is not on this device. Import the document to continue. Nothing was opened."
        case .accessRevoked:
            return "Access to this draft was revoked. Its contents are not shown."
        }
    }
}

/// The draft as this device holds it, opened at a section that exists.
public struct ResumedDraft: Hashable, Sendable {
    public let documentID: ItemID
    public let revision: Revision
    public let title: String
    public let sections: [String]
    /// The section to show, always inside `sections` when `sections` is not empty.
    public let section: Int
    /// The section the hint asked for, which may be past the end of a changed draft.
    public let requestedSection: Int
    public let clamped: Bool
    /// The stored revision is newer than the revision the hint named.
    public let newerRevision: Bool

    public var sectionText: String {
        sections.indices.contains(section) ? sections[section] : ""
    }
}

/// Advertises a continuation and resumes one. Both go through the backend, so a view, a pasted
/// link, and a Handoff activity call the same checks.
public struct PickUpResolver: Sendable {
    private let backend: any PickUpBackend

    public init(backend: any PickUpBackend) {
        self.backend = backend
    }

    /// The hint and the explicit document for a draft this actor may read, at a section that
    /// exists in it now. A revoked or missing draft produces no document.
    public func prepare(item id: ItemID, section: Int) async throws(PickUpError) -> ContinuationOffer {
        if Task.isCancelled { throw .cancelled }
        let item = try await readableItem(id)
        if Task.isCancelled { throw .cancelled }
        let sections = DraftText.sections(in: item.note.value)
        guard sections.indices.contains(section) else { throw .invalidPayload }
        let position = try SectionPosition(section: section)
        let token = ContinuationToken(
            locator: DocumentLocator(documentID: item.id, revision: item.revision),
            position: position
        )
        let document = try ContinuationDocument(item: item)
        return ContinuationOffer(token: token, document: document)
    }

    /// Looks the hint up in this lab. A missing draft asks for an import. A revoked draft returns
    /// no words, and the item is not read. A newer, shorter draft clamps the section into range.
    public func resume(_ token: ContinuationToken) async throws(PickUpError) -> ResumeDecision {
        if Task.isCancelled { throw .cancelled }
        switch try await backend.access(to: token.locator.documentID) {
        case .revoked:
            return .accessRevoked(token.locator)
        case .permitted:
            break
        }
        if Task.isCancelled { throw .cancelled }
        guard let item = try await backend.item(token.locator.documentID) else {
            return .needsImport(token.locator)
        }
        if Task.isCancelled { throw .cancelled }
        let sections = DraftText.sections(in: item.note.value)
        let landed = DraftText.clamp(token.position.section, count: sections.count)
        return .resumed(ResumedDraft(
            documentID: item.id,
            revision: item.revision,
            title: item.title.value,
            sections: sections,
            section: landed.section,
            requestedSection: token.position.section,
            clamped: landed.clamped,
            newerRevision: item.revision > token.locator.revision
        ))
    }

    private func readableItem(_ id: ItemID) async throws(PickUpError) -> LabItem {
        switch try await backend.access(to: id) {
        case .revoked: throw .notAuthorized
        case .permitted: break
        }
        guard let item = try await backend.item(id) else { throw .missing }
        return item
    }
}

/// Imports a continuation document through the backend's commit, which is the operation service.
///
/// An item already stored under the document's ID is left as it is: importing never overwrites a
/// newer copy, and it never adds a second item with the same ID. The request ID derives from the
/// document's bytes and the collection, so a retry of the same import replays its receipt.
public enum ContinuationImporter {
    public struct Result: Hashable, Sendable {
        public let itemID: ItemID
        /// The receipt of the create, or `nil` when the item was already in the lab and nothing was written.
        public let receipt: ActionReceipt?
    }

    public static func importDocument(
        _ document: ContinuationDocument,
        into collectionID: CollectionID,
        backend: any PickUpBackend
    ) async throws(PickUpError) -> Result {
        if Task.isCancelled { throw .cancelled }
        switch try await backend.access(to: document.documentID) {
        case .revoked: throw .notAuthorized
        case .permitted: break
        }
        if Task.isCancelled { throw .cancelled }
        if try await backend.item(document.documentID) != nil {
            return Result(itemID: document.documentID, receipt: nil)
        }
        let title: EntityTitle
        let note: ItemNote
        do {
            title = try EntityTitle(document.title)
            note = try ItemNote(document.note)
        } catch {
            throw .invalidPayload
        }
        let draft = ItemDraft(id: document.documentID, in: collectionID, title: title, note: note)
        let receipt = try await backend.commit(
            .createItem(draft: draft),
            requestID: ContinuationRequest.create(document, into: collectionID),
            names: [.item(document.documentID): document.title, .collection(collectionID): ""]
        )
        return Result(itemID: document.documentID, receipt: receipt)
    }
}

enum ContinuationRequest {
    static func create(_ document: ContinuationDocument, into collection: CollectionID) -> RequestID {
        let digest = ContentDigest.sha256(document.encoded())
        let mixed = ContentDigest.sha256(
            Data("native-lab/pick-up-here/create/\(digest.hex)/\(collection.rawValue.uuidString)".utf8)
        )
        return RequestID(rawValue: uuid(from: mixed))
    }

    /// A version-8 UUID from the first 16 bytes of a SHA-256 digest.
    private static func uuid(from digest: ContentDigest) -> UUID {
        var raw = Array(digest.bytes.prefix(16))
        raw[6] = (raw[6] & 0x0F) | 0x80
        raw[8] = (raw[8] & 0x3F) | 0x80
        return UUID(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
        ))
    }
}
