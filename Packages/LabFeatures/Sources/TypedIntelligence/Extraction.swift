import LabDomain

/// Where a proposal's first draft came from. The interface labels every proposal with it, so a
/// non-model path never passes for the model.
public enum ProposalSource: String, Hashable, Sendable, CaseIterable {
    /// Apple Intelligence's on-device model, through Foundation Models.
    case onDeviceModel = "on-device-model"
    /// The deterministic sample parser. Not a model.
    case sampleParser = "sample-parser"
    /// A person wrote the change in the editor. Not a model.
    case manualEditor = "manual-editor"

    public var isModel: Bool { self == .onDeviceModel }

    public var title: String {
        switch self {
        case .onDeviceModel: "On-device model"
        case .sampleParser: "Sample parser (not a model)"
        case .manualEditor: "Manual editor (not a model)"
        }
    }
}

/// One demo sample an extractor may propose to edit, as the proposer read it.
public struct SampleCandidate: Hashable, Sendable, Identifiable {
    public let item: LabItem

    public init(_ item: LabItem) {
        self.item = item
    }

    public var id: ItemID { item.id }
    public var title: String { item.title.value }
    public var note: String { item.note.value }
}

/// What an extractor produced, before any validation. Every field is untrusted text: the on-device
/// model, the sample parser, and a test's hostile fake all return this same shape, and
/// `ProposalValidator` decides what, if anything, it may become.
public struct ExtractionDraft: Hashable, Sendable {
    /// The title of the sample the note is about, as the extractor named it. Empty when unsure.
    public var sampleTitle: String
    /// Titles of other samples the note could mean.
    public var otherPossibleSamples: [String]
    /// The sample's new title. The current title keeps it.
    public var newTitle: String
    /// Text to add to the sample's note. Empty adds nothing.
    public var addedNote: String
    /// Phrases the extractor says it copied from the note.
    public var evidence: [String]

    public init(
        sampleTitle: String,
        otherPossibleSamples: [String] = [],
        newTitle: String,
        addedNote: String,
        evidence: [String] = []
    ) {
        self.sampleTitle = sampleTitle
        self.otherPossibleSamples = otherPossibleSamples
        self.newTitle = newTitle
        self.addedNote = addedNote
        self.evidence = evidence
    }
}

/// Everything an extractor is given: the note, the samples it may name, and a read-only lookup.
/// It is never given the backend, the service, or any way to commit.
public struct ExtractionRequest: Sendable {
    public let note: SourceNote
    public let candidates: [SampleCandidate]
    public let lookup: SampleLookup

    public init(note: SourceNote, candidates: [SampleCandidate], lookup: SampleLookup) {
        self.note = note
        self.candidates = candidates
        self.lookup = lookup
    }
}

/// Turns a note into a draft. Implementations never see the store and cannot commit.
public protocol NoteExtractor: Sendable {
    var source: ProposalSource { get }
    func extract(_ request: ExtractionRequest) async throws(ExtractionFailure) -> ExtractionDraft
}

/// Why no draft was produced. Nothing is proposed and nothing is stored after any of these.
public enum ExtractionFailure: Error, Hashable, Sendable {
    /// Checked again for this request, the model could not run.
    case modelUnavailable(ModelUnavailability)
    /// The model's output could not be read as the typed draft.
    case malformedOutput
    /// The model's safety checks declined the request or the model refused it.
    case refused
    case unsupportedLanguage
    case contextTooLarge
    /// The model is busy with other requests or rate-limited.
    case busy
    case timedOut(limit: Duration)
    case cancelled
    /// There are no demo samples to propose an edit to.
    case noSamples
    case other

    public var message: String {
        switch self {
        case .modelUnavailable(let reason): reason.message
        case .malformedOutput: "The model's answer did not fit the proposal's shape, so it was discarded. Try again, or use the sample parser or the manual editor."
        case .refused: "The model declined this note. Use the sample parser or the manual editor."
        case .unsupportedLanguage: "The model does not support this note's language here. Use the sample parser or the manual editor."
        case .contextTooLarge: "The note and samples are too long for the model. Use the sample parser or the manual editor."
        case .busy: "The model is busy. Try again in a moment, or use the sample parser or the manual editor."
        case .timedOut(let limit): "No draft after \(limit.components.seconds) seconds, so it was stopped. Nothing was proposed."
        case .cancelled: "Drafting was cancelled. Nothing was proposed."
        case .noSamples: "There are no demo samples to edit. Reset Demo restores them."
        case .other: "Drafting failed. Nothing was proposed."
        }
    }

    var diagnosticCategory: DiagnosticCategory {
        switch self {
        case .modelUnavailable, .unsupportedLanguage, .busy, .timedOut, .noSamples: .unavailable
        case .malformedOutput: .malformedData
        case .refused: .unsupported
        case .contextTooLarge: .tooLarge
        case .cancelled: .cancelled
        case .other: .other
        }
    }
}

/// Why the on-device model cannot run, read from `SystemLanguageModel` for one request.
public enum ModelUnavailability: String, Hashable, Sendable, CaseIterable {
    case deviceNotEligible = "device-not-eligible"
    case appleIntelligenceNotEnabled = "apple-intelligence-not-enabled"
    case modelNotReady = "model-not-ready"
    case localeNotSupported = "locale-not-supported"
    /// The SDK reported a reason this build does not recognize.
    case unrecognized
    /// FoundationModels is not part of this platform's build.
    case notCompiled = "not-compiled"

    public var message: String {
        switch self {
        case .deviceNotEligible: "This device cannot run Apple Intelligence's on-device model."
        case .appleIntelligenceNotEnabled: "Apple Intelligence is turned off in Settings."
        case .modelNotReady: "The on-device model is not ready yet. The system may still be downloading it."
        case .localeNotSupported: "The on-device model does not support this device's language setting."
        case .unrecognized: "The on-device model reported a state this build does not recognize."
        case .notCompiled: "This build has no on-device model support on this platform."
        }
    }
}
