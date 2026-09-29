import Foundation

/// The result of adopting one staged import.
public struct ImportAdoption: Hashable, Sendable {
    public let receipt: ActionReceipt
    /// `true` when the same content was already adopted into the same collection, so the
    /// original receipt was returned and nothing new was stored.
    public let isDuplicate: Bool
}

/// Adopts a reviewed staging record into the store through `OperationService`, the one path
/// every adapter uses.
///
/// Imported content is data only. The adopter turns a record into exactly one operation, a new
/// item in the collection the host chose, with the record's text or link as the item's title and
/// note. Nothing in the record selects the operation, the target, the adapter, or a permission,
/// and nothing in it can create or extend a grant. The commit runs under the adapter the host
/// composed the adopter with (the share extension by default, whose ceiling excludes destructive
/// changes), and it needs a live grant for that exact change, checked by the ledger here and again
/// by `GrantAuthorizationPolicy` at commit.
///
/// The item's ID and the request ID are derived from the content digest and the collection, so
/// adopting the same content into the same collection again returns the original receipt instead
/// of adding a copy. A cancelled or refused adoption commits nothing; the record stays waiting
/// (or, if it no longer validates, in quarantine).
public struct ImportAdopter: Sendable {
    private let service: OperationService
    private let inbox: any StagingInbox
    private let ledger: GrantLedger
    private let actor: ActorScope
    private let diagnostics: DiagnosticsLog?
    private let subject: DiagnosticSubject?

    /// - Parameters:
    ///   - adapter: The entry point the content arrived through. Use `.shareExtension` for
    ///     shared content, and `.appUI` only for the host's own paste and file-picker fallbacks.
    public init(
        service: OperationService,
        inbox: any StagingInbox,
        ledger: GrantLedger,
        adapter: AdapterKind = .shareExtension,
        diagnostics: DiagnosticsLog? = nil,
        subject: DiagnosticSubject? = nil
    ) {
        self.service = service
        self.inbox = inbox
        self.ledger = ledger
        actor = ActorScope(adapter: adapter, grants: [.read, .commit])
        self.diagnostics = diagnostics
        self.subject = subject
    }

    /// The adapter this adopter commits as. Issue the approval grant to it.
    public var adapter: AdapterKind { actor.adapter }

    /// The grant target a person approves when they choose to add an import to `collection`.
    public static func grantTarget(into collection: CollectionID) -> GrantTarget { .newItem(in: collection) }

    /// Validates the waiting record again, then commits it as a new item in `collection`.
    public func adopt(_ id: StagingID, into collection: CollectionID) async throws(ImportRejection) -> ImportAdoption {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let adoption = try await adoptChecked(id, into: collection)
            diagnostics?.record(
                "import.adopt", outcome: .succeeded, subject: subject, duration: clock.now - start,
                counts: ["duplicate": adoption.isDuplicate ? 1 : 0]
            )
            return adoption
        } catch {
            diagnostics?.record("import.adopt", failure: error, subject: subject, duration: clock.now - start)
            throw error
        }
    }

    private func adoptChecked(_ id: StagingID, into collection: CollectionID) async throws(ImportRejection) -> ImportAdoption {
        guard !Task.isCancelled else { throw .cancelled }
        let record = try await inbox.validatedRecord(id)
        let operation = try Self.operation(for: record, into: collection)
        let requestID = Self.requestID(for: record, into: collection)

        // Fail closed with a specific reason before touching the service. The service's policy
        // checks the same grant again at commit.
        switch ledger.check(operation, from: actor.adapter) {
        case .granted: break
        case .missing: throw .grantMissing
        case .expired: throw .grantExpired
        case .outOfScope: throw .grantOutOfScope
        }

        let alreadyAdopted: Bool
        do {
            alreadyAdopted = try await service.findReceipt(for: requestID, as: actor) != nil
        } catch {
            throw map(error, operation: operation)
        }

        guard !Task.isCancelled else { throw .cancelled }
        let receipt: ActionReceipt
        do {
            receipt = try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw map(error, operation: operation)
        }
        // The commit is durable now. Clearing staging can fail or be retried; a retry replays
        // the recorded receipt and clears it then.
        try await inbox.markAdopted(id)
        return ImportAdoption(receipt: receipt, isDuplicate: alreadyAdopted)
    }

    // MARK: Mapping content to one operation

    /// The one operation adoption commits for `record`: a new item in `collection`.
    ///
    /// Text becomes the note, and its first line (shortened to fit) the title. A link becomes the
    /// note, and its page title, or else its host, the title. Files cannot be adopted yet: the
    /// domain has no attachment entity.
    public static func operation(for record: StagingRecord, into collection: CollectionID) throws(ImportRejection) -> DomainOperation {
        let titleSource: String
        let noteText: String
        switch record.payload {
        case .text(let text):
            titleSource = text
            noteText = text
        case .link(let url, let pageTitle):
            let trimmedTitle = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            titleSource = trimmedTitle.isEmpty ? (url.host() ?? url.absoluteString) : trimmedTitle
            noteText = url.absoluteString
        case .files:
            throw .attachmentsNotAdoptable
        }
        guard noteText.count <= ItemNote.maximumLength else { throw .textTooLongForNote(limit: ItemNote.maximumLength) }
        let title: EntityTitle
        let note: ItemNote
        do {
            title = try EntityTitle(Self.titleLine(from: titleSource))
            note = try ItemNote(noteText)
        } catch {
            throw .unsupportedCharacters
        }
        let itemID = ItemID(rawValue: record.digest.derivedUUID("item", collection.rawValue.bytes))
        return .createItem(draft: ItemDraft(id: itemID, in: collection, title: title, note: note))
    }

    /// The request ID adoption of `record` into `collection` always uses.
    public static func requestID(for record: StagingRecord, into collection: CollectionID) -> RequestID {
        RequestID(rawValue: record.digest.derivedUUID("request", collection.rawValue.bytes))
    }

    /// The first non-blank line, with tabs as spaces, shortened to fit a title.
    static func titleLine(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { line in
                let spaced = line.unicodeScalars.map { $0.properties.generalCategory == .control ? " " : $0 }
                return String(String.UnicodeScalarView(spaced)).trimmingCharacters(in: .whitespaces)
            }
            .first { !$0.isEmpty } ?? ""
        guard line.count > EntityTitle.maximumLength else { return line }
        return String(line.prefix(EntityTitle.maximumLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func map(_ error: OperationError, operation: DomainOperation) -> ImportRejection {
        switch error {
        case .unauthorized:
            // Say why the grant no longer covers the commit, if that is the reason.
            switch ledger.check(operation, from: actor.adapter) {
            case .granted: return .notAuthorized
            case .missing: return .grantMissing
            case .expired: return .grantExpired
            case .outOfScope: return .grantOutOfScope
            }
        case .notFound, .ruleViolation(.collectionArchived), .ruleViolation(.demoCollection):
            return .destinationUnavailable
        case .ruleViolation, .requestIDReused:
            return .identifierConflict
        case .invalidPayload:
            return .unsupportedCharacters
        case .storeFailure:
            return .storeUnavailable
        }
    }
}

extension UUID {
    var bytes: [UInt8] {
        withUnsafeBytes(of: uuid) { Array($0) }
    }
}
