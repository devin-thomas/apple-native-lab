import LabDomain

/// LAB-010 Typed Local Intelligence: an ambiguous note becomes a typed proposal to edit one demo
/// sample, a person reviews and edits it, and only then does the app UI commit it.
///
/// AI proposes; deterministic code commits (ADR-007). Every extractor, the on-device model and the
/// non-model sample parser alike, reads and proposes as the model-tool adapter, whose fixed ceiling
/// is read and propose (ADR-011). The only way into the store is `TypedIntelligenceBackend.commit`,
/// which takes an `ApprovedChange`, and only `ReviewableProposal.approve()` makes one.
public enum TypedIntelligence {
    public static let experimentID = "LAB-010"

    /// The scope every extractor reads and proposes with. Its adapter can never commit, whatever
    /// it is granted, so nothing an extractor produces reaches the store on its own.
    public static let proposer = ActorScope(adapter: .modelTool, grants: [.read, .propose])

    /// How long a draft may take before it is abandoned and the person is told.
    public static let defaultTimeLimit: Duration = .seconds(30)

    static let diagnosticSubject = DiagnosticSubject("LAB-010")
}

/// The experiment's own bounds. They are tighter than the domain's where a proposal is concerned,
/// so a draft that fits them always fits the domain too.
public enum ProposalLimits {
    /// A source note, in characters. Longer notes are refused before any extractor sees them.
    public static let sourceNote = 2_000
    /// A proposed title, in characters. The domain allows `EntityTitle.maximumLength`.
    public static let title = 60
    /// Text a proposal adds to a sample's note, in characters.
    public static let addedNote = 280
    /// Evidence quotes kept per proposal.
    public static let evidenceCount = 3
    /// The length of one evidence quote, in characters.
    public static let evidenceLength = 3...200
    /// Other samples a proposal may say the note could mean.
    public static let otherSamples = 3
    /// Samples offered to an extractor.
    public static let candidates = 50
    /// Results one lookup-tool call returns.
    public static let lookupResults = 5
    /// Characters of a sample's note one lookup result shows.
    public static let lookupNoteLength = 120
    /// Characters of a lookup-tool search word.
    public static let lookupWord = 40
}
