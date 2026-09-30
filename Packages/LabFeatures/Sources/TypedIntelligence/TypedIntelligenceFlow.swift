import LabDomain

/// The experiment's one path: read the samples, draft, validate, check with the service, and,
/// after a person approves, commit.
///
/// Every step before `commit` runs as the proposer, and none of them records anything. Diagnostics
/// hold phases, outcomes, categories, durations, and counts only: never the note, the prompt, the
/// draft, or a sample's text.
public struct TypedIntelligenceFlow: Sendable {
    private let backend: any TypedIntelligenceBackend
    private let diagnostics: DiagnosticsLog?
    public let timeLimit: Duration

    public init(
        backend: any TypedIntelligenceBackend,
        diagnostics: DiagnosticsLog? = nil,
        timeLimit: Duration = TypedIntelligence.defaultTimeLimit
    ) {
        self.backend = backend
        self.diagnostics = diagnostics
        self.timeLimit = timeLimit
    }

    /// The demo samples a note may be about, read as the proposer and ordered by title. Archived
    /// samples and the person's own items are never offered.
    public func candidates() async throws(IntelligenceError) -> [SampleCandidate] {
        let filter: ItemFilter
        do {
            filter = try ItemFilter(includeArchived: false, limit: ItemFilter.allowedLimits.upperBound)
        } catch {
            throw .refused(.invalidPayload(error))
        }
        let items = try await backend.items(filter)
        return Array(items
            .filter { $0.namespace == .demo && !$0.isArchived }
            .prefix(ProposalLimits.candidates)
            .map(SampleCandidate.init))
    }

    /// Drafts a proposal from `note` with `extractor`, then validates it and checks its operation
    /// with the service. The extractor gets the note, the candidates, and a read-only lookup; it
    /// is stopped after `timeLimit` or when the calling task is cancelled.
    public func draft(
        _ note: SourceNote,
        with extractor: any NoteExtractor,
        candidates: [SampleCandidate]
    ) async -> Result<ReviewableProposal, ExtractionFailure> {
        let phase = Self.draftPhase(extractor.source)
        let clock = ContinuousClock()
        let start = clock.now
        let counts: [DiagnosticName: Int] = ["candidates": candidates.count]
        guard !candidates.isEmpty else {
            record(phase, failure: .noSamples, duration: clock.now - start, counts: counts)
            return .failure(.noSamples)
        }
        if Task.isCancelled {
            record(phase, failure: .cancelled, duration: clock.now - start, counts: counts)
            return .failure(.cancelled)
        }
        let backend = backend
        let request = ExtractionRequest(note: note, candidates: candidates, lookup: SampleLookup(candidates: candidates) { filter in
            (try? await backend.items(filter)) ?? []
        })
        let result = await TimeLimit.run(limit: timeLimit) { () async throws(ExtractionFailure) -> ExtractionDraft in
            try await extractor.extract(request)
        }
        let draft: ExtractionDraft
        switch result {
        case .failure(let failure):
            record(phase, failure: failure, duration: clock.now - start, counts: counts)
            return .failure(failure)
        case .success(let value):
            draft = value
        }
        if Task.isCancelled {
            record(phase, failure: .cancelled, duration: clock.now - start, counts: counts)
            return .failure(.cancelled)
        }
        let proposal = ProposalValidator.validate(ProposalFields(draft), source: extractor.source, note: note, candidates: candidates)
        let reviewable = ReviewableProposal(proposal: proposal, serviceCheck: await check(proposal))
        diagnostics?.record(
            phase, outcome: .succeeded, subject: TypedIntelligence.diagnosticSubject,
            duration: clock.now - start, counts: Self.counts(reviewable, candidates: candidates.count)
        )
        return .success(reviewable)
    }

    /// Validates fields a person edited, then checks the operation with the service.
    public func revise(
        _ fields: ProposalFields,
        source: ProposalSource,
        note: SourceNote,
        candidates: [SampleCandidate]
    ) async -> ReviewableProposal {
        let proposal = ProposalValidator.validate(fields, source: source, editedByPerson: true, note: note, candidates: candidates)
        let reviewable = ReviewableProposal(proposal: proposal, serviceCheck: await check(proposal))
        diagnostics?.record(
            "intelligence.review", outcome: reviewable.isApprovable ? .succeeded : .rejected,
            subject: TypedIntelligence.diagnosticSubject,
            category: reviewable.isApprovable ? nil : .invalidInput,
            counts: Self.counts(reviewable, candidates: candidates.count)
        )
        return reviewable
    }

    /// Commits a person's approved change as the app UI. The receipt may be a conflict, in which
    /// case nothing changed.
    public func commit(_ change: ApprovedChange) async throws(IntelligenceError) -> ActionReceipt {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let receipt = try await backend.commit(change)
            let outcome: DiagnosticOutcome = receipt.conflict == nil ? .succeeded : .rejected
            diagnostics?.record(
                "intelligence.commit", outcome: outcome, subject: TypedIntelligence.diagnosticSubject,
                category: receipt.conflict == nil ? nil : .conflict, duration: clock.now - start,
                counts: ["model": change.source.isModel ? 1 : 0, "edited": change.editedByPerson ? 1 : 0]
            )
            return receipt
        } catch {
            diagnostics?.record(
                "intelligence.commit", failure: Self.underlying(error), subject: TypedIntelligence.diagnosticSubject,
                duration: clock.now - start
            )
            throw error
        }
    }

    // MARK: Internals

    private func check(_ proposal: ExtractionProposal) async -> ServiceCheck {
        guard let operation = proposal.operation else { return .notChecked }
        do {
            let checked = try await backend.propose(operation)
            if let conflict = checked.conflict { return .stale(conflict) }
            return .accepted(checked)
        } catch {
            switch error {
            case .refused(let refusal): return .refused(refusal)
            case .unavailable: return .refused(.storeFailure(.readFailed))
            }
        }
    }

    private func record(_ phase: DiagnosticName, failure: ExtractionFailure, duration: Duration, counts: [DiagnosticName: Int]) {
        let category = failure.diagnosticCategory
        diagnostics?.record(
            phase, outcome: category.outcome, subject: TypedIntelligence.diagnosticSubject,
            category: category, duration: duration, counts: counts
        )
    }

    private static func draftPhase(_ source: ProposalSource) -> DiagnosticName {
        switch source {
        case .onDeviceModel: "intelligence.draft.model"
        case .sampleParser: "intelligence.draft.parser"
        case .manualEditor: "intelligence.draft.manual"
        }
    }

    private static func counts(_ reviewable: ReviewableProposal, candidates: Int) -> [DiagnosticName: Int] {
        let issues = reviewable.issues
        return [
            "candidates": candidates,
            "blocking": issues.count(where: \.isBlocking),
            "advisories": issues.count(where: { !$0.isBlocking }),
            "evidence": reviewable.proposal.evidence.count,
            "approvable": reviewable.isApprovable ? 1 : 0,
        ]
    }

    private static func underlying(_ error: IntelligenceError) -> any Error {
        switch error {
        case .refused(let refusal): refusal
        case .unavailable: StoreUnavailable()
        }
    }
}

/// Classified as `other` by the diagnostics facade; the reason sentence is never logged.
private struct StoreUnavailable: Error {}
