import Foundation
import LabDomain

/// A phrase from the source note that supports a proposal, found in the note word for word.
///
/// Evidence shows why a proposal says what it says. It does not make the proposal true: a quote
/// can be real and still be read wrongly, which is why a person reviews every proposal.
public struct EvidenceSpan: Hashable, Sendable {
    public let quote: String
    /// Where the quote starts in the note, in characters.
    public let offset: Int
    public var length: Int { quote.count }
}

/// One problem found in a proposal. A blocking issue keeps the proposal from becoming an operation
/// until the person fixes it in the editor; an advisory one is shown beside it for review.
public enum ValidationIssue: Hashable, Sendable {
    // Blocking
    /// No sample was named, or the name was left empty.
    case noSampleChosen
    /// The named sample is not one of the samples offered.
    case unknownSample
    /// More than one offered sample has the named title.
    case sampleNameMatchesSeveral(count: Int)
    case sampleArchived
    case titleEmpty
    case titleTooLong(limit: Int)
    case titleHasControlCharacters
    case addedNoteTooLong(limit: Int)
    case addedNoteHasControlCharacters
    /// The sample's note plus the added text would exceed the domain's note limit.
    case noteWouldBeTooLong(limit: Int)
    /// The proposal would leave the sample as it is.
    case noChange
    /// The sample changed after it was read. Read it again before approving.
    case sampleChanged(RevisionConflict)
    /// The operation service refused the proposal.
    case refusedByService(OperationError)

    // Advisory
    /// The note could also mean these samples.
    case otherPossibleSamples([String])
    /// The note names these samples outright, and the draft neither chose nor listed them.
    case noteNamesOtherSamples([String])
    /// Quotes the extractor gave that are not in the note, word for word. They were dropped.
    case evidenceNotInNote(count: Int)
    /// Nothing in the note was quoted in support of this proposal.
    case noEvidence
    /// The sample's note already contains the text the proposal adds.
    case addedNoteAlreadyPresent

    public var isBlocking: Bool {
        switch self {
        case .otherPossibleSamples, .noteNamesOtherSamples, .evidenceNotInNote, .noEvidence, .addedNoteAlreadyPresent: false
        default: true
        }
    }

    /// A sentence for the person reviewing the proposal.
    public var message: String {
        switch self {
        case .noSampleChosen: "Choose the sample this note is about."
        case .unknownSample: "The proposal names a sample that is not in the demo. Choose one of the samples."
        case .sampleNameMatchesSeveral(let count): "\(count) samples have that title. Choose the one this note is about."
        case .sampleArchived: "That sample is archived. Restore it first, or choose another."
        case .titleEmpty: "A title is required."
        case .titleTooLong(let limit): "Shorten the title to \(limit) characters or fewer."
        case .titleHasControlCharacters: "The title contains control characters or a line break."
        case .addedNoteTooLong(let limit): "Shorten the added note to \(limit) characters or fewer."
        case .addedNoteHasControlCharacters: "The added note contains control characters."
        case .noteWouldBeTooLong(let limit): "With this addition the sample's note would pass \(limit) characters."
        case .noChange: "This would leave the sample as it is. Change the title or add to the note."
        case .sampleChanged: "The sample changed after it was read. Read it again, then review the change."
        case .refusedByService(let error): ServiceRefusal.sentence(for: error)
        case .otherPossibleSamples(let titles): "The note could also mean \(ListFormatting.join(titles)). Check the sample before you apply."
        case .noteNamesOtherSamples(let titles): "The note also names \(ListFormatting.join(titles, conjunction: "and")). Make sure this is the right sample."
        case .evidenceNotInNote(let count): count == 1
            ? "One quote the draft gave is not in the note, so it was dropped."
            : "\(count) quotes the draft gave are not in the note, so they were dropped."
        case .noEvidence: "Nothing in the note was quoted to support this. Check it against the note."
        case .addedNoteAlreadyPresent: "The sample's note already says this."
        }
    }
}

/// What a proposal would change on its sample.
public struct SampleDiff: Hashable, Sendable {
    public let titleBefore: String
    public let titleAfter: String
    public let noteBefore: String
    public let noteAfter: String

    public var changesTitle: Bool { titleBefore != titleAfter }
    public var changesNote: Bool { noteBefore != noteAfter }
}

/// A proposal after deterministic validation: the typed fields, the evidence that survived, every
/// issue, and the operation it would submit if nothing blocks it.
///
/// It is a value computed from a draft and the samples as read; it holds no reference to the store
/// and cannot commit. The operation is a `.updateItem` pinned to the revision that was read.
public struct ExtractionProposal: Hashable, Sendable {
    public let source: ProposalSource
    /// Whether a person changed any field after the draft.
    public let editedByPerson: Bool
    public let target: SampleCandidate?
    public let newTitle: String
    public let addedNote: String
    public let evidence: [EvidenceSpan]
    public let otherPossibleSamples: [SampleCandidate]
    public let issues: [ValidationIssue]
    public let diff: SampleDiff?
    /// The change to submit, or `nil` while any issue blocks it.
    public let operation: DomainOperation?

    public var isBlocked: Bool { operation == nil }
    public var blockingIssues: [ValidationIssue] { issues.filter(\.isBlocking) }
    public var advisories: [ValidationIssue] { issues.filter { !$0.isBlocking } }
}

/// The fields a proposal is built from: a draft's, or the editor's after a person changed them.
public struct ProposalFields: Hashable, Sendable {
    public enum Target: Hashable, Sendable {
        case none
        /// A sample named by title, as an extractor names it.
        case title(String)
        /// A sample chosen by identity, as a person chooses it in the editor.
        case item(ItemID)
    }

    public var target: Target
    public var newTitle: String
    public var addedNote: String
    public var evidence: [String]
    public var otherPossibleSamples: [String]

    public init(target: Target, newTitle: String, addedNote: String, evidence: [String] = [], otherPossibleSamples: [String] = []) {
        self.target = target
        self.newTitle = newTitle
        self.addedNote = addedNote
        self.evidence = evidence
        self.otherPossibleSamples = otherPossibleSamples
    }

    public init(_ draft: ExtractionDraft) {
        let name = draft.sampleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            target: name.isEmpty ? .none : .title(name),
            newTitle: draft.newTitle,
            addedNote: draft.addedNote,
            evidence: draft.evidence,
            otherPossibleSamples: draft.otherPossibleSamples
        )
    }
}

enum ListFormatting {
    static func join(_ items: [String], conjunction: String = "or") -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) \(conjunction) \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", \(conjunction) \(items[items.count - 1])"
        }
    }
}

/// Readable sentences for the service's refusals of a proposal.
enum ServiceRefusal {
    static func sentence(for error: OperationError) -> String {
        switch error {
        case .unauthorized: "The proposer is not allowed to do this. Nothing was changed."
        case .notFound: "That sample no longer exists. Choose another."
        case .ruleViolation(.archived): "That sample is archived. Restore it first, or choose another."
        case .ruleViolation(.noChanges): "This would leave the sample as it is."
        case .ruleViolation: "The lab's rules do not allow this change."
        case .invalidPayload: "A field is not valid."
        case .requestIDReused: "That request was already used for a different change."
        case .storeFailure: "The lab store could not be read. Try again."
        }
    }
}
