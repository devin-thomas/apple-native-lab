import Foundation
import LabDomain
import LabSupport
import Observation
import TypedIntelligence

/// One note's session in Typed Local Intelligence: the probe, a draft from the chosen source, the
/// person's edits, and the change they apply.
///
/// Drafting runs off the main actor through `TypedIntelligenceFlow`, is cancellable, and stops at
/// the flow's time limit. Every edit is validated again and checked with the service as the
/// proposer. Apply is the only step that commits, and only for the proposal on screen.
@MainActor
@Observable
final class IntelligenceWorkbench {
    enum Phase: Hashable {
        case loading
        /// Ready to draft. No proposal is under review.
        case ready
        case drafting(ProposalSource)
        case reviewing
        case applying
    }

    let fixture: IntelligenceFixture
    private(set) var phase: Phase = .loading
    private(set) var note: SourceNote?
    private(set) var readiness: ModelReadiness?
    private(set) var candidates: [SampleCandidate] = []
    /// The latest validated proposal for the editor's fields.
    private(set) var review: ReviewableProposal?
    /// The source of the draft under review.
    private(set) var source: ProposalSource?
    /// Quotes the draft gave that were not in the note. They were dropped before review.
    private(set) var droppedQuotes = 0
    /// Why the last step failed, as a sentence for the person.
    private(set) var message: String?
    /// The receipt of the last change applied, including a conflict that changed nothing.
    private(set) var applied: ReceiptRecord?
    /// True from an edit until its validation returns. Apply waits for it.
    private(set) var isRevising = false

    // The editor's fields. Views bind to them and call `fieldsChanged()`.
    var targetID: ItemID?
    var title = ""
    var addedNote = ""
    private var evidence: [String] = []
    private var otherPossible: [String] = []

    @ObservationIgnored private var library: LabLibrary?
    @ObservationIgnored private var flow: TypedIntelligenceFlow?
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored private var revisionTask: Task<Void, Never>?
    /// The approval for the proposal on screen, kept so a retry after a failure is the same request.
    @ObservationIgnored private var approval: (review: ReviewableProposal, change: ApprovedChange)?
    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private let registry: CapabilityRegistry
    @ObservationIgnored private let timeLimit: Duration

    init(
        fixture: IntelligenceFixture,
        bundle: Bundle = .main,
        registry: CapabilityRegistry = .live(),
        timeLimit: Duration = TypedIntelligence.defaultTimeLimit
    ) {
        self.fixture = fixture
        self.bundle = bundle
        self.registry = registry
        self.timeLimit = timeLimit
    }

    // MARK: Lifecycle

    func start(with library: LabLibrary) async {
        guard self.library == nil else { return }
        self.library = library
        flow = TypedIntelligenceFlow(
            backend: LibraryIntelligenceBackend(library: library),
            diagnostics: IntelligenceDiagnostics.log,
            timeLimit: timeLimit
        )
        do {
            note = try fixture.load(from: bundle)
        } catch {
            message = error.message
        }
        readiness = await ModelReadiness.probe(registry)
        await readSamples()
        phase = .ready
    }

    /// Stops a draft in progress. The flow returns at once and nothing is proposed.
    func cancelDraft() {
        draftTask?.cancel()
    }

    // MARK: Drafting

    var isBusy: Bool {
        switch phase {
        case .loading, .drafting, .applying: true
        case .ready, .reviewing: false
        }
    }

    var drafting: ProposalSource? {
        if case .drafting(let source) = phase { source } else { nil }
    }

    /// Whether the probe opened the model route and this build includes it.
    var modelIsOffered: Bool {
        readiness?.route == .model && OnDeviceModelExtractor.isCompiled
    }

    var canDraft: Bool { note != nil && !isBusy }

    /// The draft time limit in whole seconds, for the progress message.
    var timeLimitSeconds: Int64 { timeLimit.components.seconds }

    /// Starts a draft from `source`. The manual editor starts an empty proposal instead.
    func draft(with source: ProposalSource) {
        guard let flow, let note, canDraft else { return }
        if source == .onDeviceModel, !modelIsOffered { return }
        cancelRevision()
        clearProposal()
        applied = nil
        message = nil
        if source == .manualEditor {
            self.source = .manualEditor
            phase = .reviewing
            fieldsChanged()
            return
        }
        phase = .drafting(source)
        let extractor: any NoteExtractor = source == .onDeviceModel ? OnDeviceModelExtractor() : SampleParser()
        draftTask = Task {
            // Read the samples again for every request, so the draft starts from current state.
            await readSamples()
            let result = await flow.draft(note, with: extractor, candidates: candidates)
            switch result {
            case .success(let reviewable):
                load(reviewable, from: source)
            case .failure(let failure):
                message = failure.message
                phase = .ready
                if case .modelUnavailable = failure {
                    readiness = await ModelReadiness.probe(registry)
                }
            }
            draftTask = nil
        }
    }

    private func load(_ reviewable: ReviewableProposal, from source: ProposalSource) {
        let proposal = reviewable.proposal
        self.source = source
        review = reviewable
        targetID = proposal.target?.id
        title = proposal.newTitle
        addedNote = proposal.addedNote
        evidence = proposal.evidence.map(\.quote)
        otherPossible = proposal.otherPossibleSamples.map(\.title)
        droppedQuotes = proposal.issues.reduce(0) { count, issue in
            if case .evidenceNotInNote(let dropped) = issue { count + dropped } else { count }
        }
        phase = .reviewing
    }

    // MARK: Review

    var currentFields: ProposalFields {
        ProposalFields(
            target: targetID.map(ProposalFields.Target.item) ?? .none,
            newTitle: title,
            addedNote: addedNote,
            evidence: evidence,
            otherPossibleSamples: otherPossible
        )
    }

    /// The person chose another sample. A title still naming the old sample follows the choice.
    func targetChanged(from old: ItemID?) {
        let oldTitle = old.flatMap { id in candidates.first { $0.id == id }?.title }
        if title.isEmpty || title == oldTitle, let new = candidates.first(where: { $0.id == targetID }) {
            title = new.title
        }
        fieldsChanged()
    }

    /// Validates the editor's fields again, after a short pause in typing.
    func fieldsChanged() {
        guard phase == .reviewing, let flow, let note, let source else { return }
        revisionTask?.cancel()
        isRevising = true
        let fields = currentFields
        let candidates = candidates
        revisionTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let revised = await flow.revise(fields, source: source, note: note, candidates: candidates)
            guard !Task.isCancelled else { return }
            review = revised
            isRevising = false
        }
    }

    var canApply: Bool {
        phase == .reviewing && !isRevising && review?.isApprovable == true
    }

    /// Reads the samples again and checks the fields against them, after a conflict.
    func readAgain() async {
        await readSamples()
        fieldsChanged()
    }

    /// Commits the proposal on screen as the app UI. The only step that changes anything.
    func apply() async {
        guard canApply, let flow, let review else { return }
        let change: ApprovedChange
        if let approval, approval.review == review {
            change = approval.change
        } else {
            do {
                change = try review.approve()
            } catch {
                message = error.message
                return
            }
            approval = (review, change)
        }
        phase = .applying
        do {
            let receipt = try await flow.commit(change)
            applied = library?.receipt(id: receipt.operationID)
            approval = nil
            if receipt.conflict != nil {
                message = "Not applied: the sample changed after it was read. Read it again, then review the change."
                phase = .reviewing
            } else {
                message = nil
                clearProposal()
                phase = .ready
            }
        } catch {
            message = error.message
            phase = .reviewing
        }
        await readSamples()
    }

    /// Drops the proposal. Nothing was stored for it.
    func discard() {
        cancelRevision()
        clearProposal()
        message = nil
        phase = .ready
    }

    // MARK: Internals

    private func readSamples() async {
        guard let flow else { return }
        do {
            candidates = try await flow.candidates()
        } catch {
            message = error.message
        }
    }

    private func clearProposal() {
        review = nil
        source = nil
        targetID = nil
        title = ""
        addedNote = ""
        evidence = []
        otherPossible = []
        droppedQuotes = 0
        approval = nil
        isRevising = false
    }

    private func cancelRevision() {
        revisionTask?.cancel()
        revisionTask = nil
        isRevising = false
    }
}
