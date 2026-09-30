import Foundation
import LabDomain
import LabStaging

/// Imports lab documents: stage, validate, review, then commit through the operation service.
///
/// Every import takes the same path, whatever it came from (a file picker, a drop from another
/// window or app, or the bundled sample):
///
/// 1. **Stage.** The bytes go to a `StagingArea` under the fixed name `object.anlab`, never the
///    sender's file name. Staging streams them to disk within the import limits (2 MiB for a
///    JSON document) and runs `StrictJSON` on them, so an oversized or malformed file is refused
///    there, and a refused file leaves nothing behind.
/// 2. **Validate and review.** The staged bytes are read back and checked again (size and
///    SHA-256), decoded as a `LabDocument` with every schema rule, and planned against the lab.
///    A document that fails the schema is discarded from staging with a readable reason.
/// 3. **Commit.** Only a person's choice commits, and only through the backend's
///    `OperationService`: the staged bytes are verified once more, their digest must equal the
///    reviewed one, the plan is made again against the current lab and must be the reviewed
///    decision, and one request (create or update) commits with a receipt. Nothing here writes
///    the store.
///
/// Request IDs derive from the document's digest and the commit's target, so repeating an import
/// replays its receipt, and an object the lab holds is never added twice.
public struct PortableObjectsImporter: Sendable {
    /// The name every staged document gets, so a hostile file name is never used, and staging
    /// always applies its JSON checks.
    static let stagedName = "object.\(LabDocument.fileExtension)"

    private let backend: any PortableObjectsBackend
    private let staging: StagingArea
    private let diagnostics: DiagnosticsLog?
    private static let subject = DiagnosticSubject("LAB-008")

    public var limits: ImportLimits { staging.limits }

    /// - Parameter stagingRoot: A folder in the app's own container for this importer alone.
    public init(
        backend: any PortableObjectsBackend,
        stagingRoot: URL,
        limits: ImportLimits = .standard,
        diagnostics: DiagnosticsLog? = nil
    ) throws(PortableObjectError) {
        self.backend = backend
        self.diagnostics = diagnostics
        do {
            staging = try StagingArea(root: stagingRoot, limits: limits, diagnostics: diagnostics, subject: Self.subject)
        } catch {
            throw .staging(error)
        }
    }

    // MARK: Review

    /// Stages bytes that arrived in memory, such as a drop from another window, and reviews them.
    public func review(data: Data) async throws(PortableObjectError) -> ImportReview {
        try await recorded("portable.review") { () async throws(PortableObjectError) in
            guard data.count <= limits.maximumTextBytes else {
                throw .staging(.malformedJSON(file: 1, .tooLarge(limit: limits.maximumTextBytes)))
            }
            let outcome: StagingOutcome
            do throws(ImportRejection) {
                outcome = try await staging.stageFiles([.data(data, name: Self.stagedName)])
            } catch {
                throw .staging(error)
            }
            return try await review(outcome.id)
        }
    }

    /// Stages a file a person chose, reading it in chunks within the limits, and reviews it. A
    /// security-scoped URL from a file picker is opened for the read and closed after it.
    public func review(fileAt url: URL) async throws(PortableObjectError) -> ImportReview {
        try await recorded("portable.review") { () async throws(PortableObjectError) in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let outcome: StagingOutcome
            do throws(ImportRejection) {
                outcome = try await staging.stageFiles([.contents(of: url, name: Self.stagedName)])
            } catch {
                throw .staging(error)
            }
            return try await review(outcome.id)
        }
    }

    /// Validates a staged document again from disk, decodes it, and plans it.
    private func review(_ id: StagingID) async throws(PortableObjectError) -> ImportReview {
        let (document, byteCount) = try await stagedDocument(id)
        let plan: ImportPlan
        do {
            plan = try await ImportPlan.plan(document, backend: backend)
        } catch {
            await discard(id)
            throw error
        }
        return ImportReview(id: id, document: document, digest: document.digest, plan: plan, byteCount: byteCount)
    }

    /// The staged document, read back and checked. A document that fails the schema is removed
    /// from staging, so it can never be committed or block another import.
    private func stagedDocument(_ id: StagingID) async throws(PortableObjectError) -> (LabDocument, Int) {
        let bytes: Data
        do { bytes = try await staging.contents(of: 0, in: id) } catch { throw .staging(error) }
        do {
            return (try LabDocument(decoding: bytes, limits: limits), bytes.count)
        } catch {
            await discard(id)
            throw error
        }
    }

    // MARK: Commit

    /// Commits the reviewed decision: a new item in `destination`, or the document's title and
    /// note applied to the stored item. Returns the receipt, or the one already recorded when this
    /// same decision committed before.
    public func commit(_ review: ImportReview, into destination: CollectionID? = nil) async throws(PortableObjectError) -> ImportResult {
        try await recorded("portable.commit") { () async throws(PortableObjectError) in
            try await commitChecked(review, into: destination)
        }
    }

    private func commitChecked(_ review: ImportReview, into destination: CollectionID?) async throws(PortableObjectError) -> ImportResult {
        guard !Task.isCancelled else { throw .cancelled }
        let (operation, requestID, change) = try decision(for: review, into: destination)

        // A retry of a decision that already committed gets its receipt back.
        if let recorded = try await backend.receipt(for: requestID) {
            await discard(review.id)
            return ImportResult(receipt: recorded, change: change, item: try? await backend.item(review.document.itemID), isReplay: true)
        }

        // The bytes committed are the bytes reviewed, and the lab still calls for the same change.
        let (document, _) = try await stagedDocument(review.id)
        guard document.digest == review.digest else {
            await discard(review.id)
            throw .changedSinceReview
        }
        let current = try await ImportPlan.plan(document, backend: backend)
        guard current.sameDecision(as: review.plan) else { throw .stateChanged }
        if case .create = current {
            guard let destination, let collection = try await backend.collection(destination),
                  collection.namespace == .user, !collection.isArchived
            else { throw destination == nil ? .noDestination : .destinationUnavailable }
        }

        guard !Task.isCancelled else { throw .cancelled }
        let receipt = try await backend.commit(operation, requestID: requestID, names: [.item(document.itemID): document.title])
        // The commit is durable. Clearing staging can fail; a retry replays the receipt above.
        await discard(review.id)
        return ImportResult(receipt: receipt, change: change, item: try? await backend.item(document.itemID), isReplay: false)
    }

    /// The one operation and request a reviewed plan commits.
    private func decision(
        for review: ImportReview,
        into destination: CollectionID?
    ) throws(PortableObjectError) -> (DomainOperation, RequestID, ImportResult.Change) {
        switch review.plan {
        case .create(let content):
            guard let destination else { throw .noDestination }
            let draft = ItemDraft(
                id: review.document.itemID, in: destination, title: content.title, note: content.note, extras: content.extras
            )
            return (.createItem(draft: draft), ImportRequest.create(review.digest, into: destination), .created)
        case .differs(let stored, _, let changes):
            return (
                .updateItem(id: stored.id, expected: stored.revision, changes: changes),
                ImportRequest.update(review.digest, item: stored.id, at: stored.revision),
                .updated
            )
        case .alreadyPresent:
            throw .nothingToImport
        case .refused(let reason, _):
            throw reason
        }
    }

    // MARK: Staging

    /// Removes a staged import a person closed or that is finished. Removing one already gone
    /// succeeds.
    public func discard(_ id: StagingID) async {
        try? await staging.discard(id)
    }

    /// Imports waiting in staging, oldest first: ones a stopped app left before a decision.
    public func waitingImports() async -> [StagingID] {
        await staging.waitingImports()
    }

    // MARK: Diagnostics

    private func recorded<Value: Sendable>(
        _ phase: DiagnosticName,
        _ body: () async throws(PortableObjectError) -> Value
    ) async throws(PortableObjectError) -> Value {
        let start = ContinuousClock.now
        do {
            let value = try await body()
            diagnostics?.record(phase, outcome: .succeeded, subject: Self.subject, duration: ContinuousClock.now - start)
            return value
        } catch {
            // The category alone: never a field name, a value, or a path.
            diagnostics?.record(
                phase, outcome: error.category.outcome, subject: Self.subject, category: error.category,
                duration: ContinuousClock.now - start
            )
            throw error
        }
    }
}
