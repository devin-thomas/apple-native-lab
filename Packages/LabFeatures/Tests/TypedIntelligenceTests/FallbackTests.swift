import LabDomain
import Testing
@testable import TypedIntelligence

/// LAB-010's declared fallback: the deterministic sample parser and the manual editor, labeled as
/// non-model paths, complete the whole interaction without the model.
@Suite struct FallbackTests {
    @Test func theParserReadsTheAmbiguousNoteDeterministically() async throws {
        let lab = try await Lab.seeded()
        let candidates = try await lab.candidates()
        let note = try Repository.note(.ambiguousNote)
        let draft = SampleParser.parse(note.text, candidates: candidates)
        #expect(draft == SampleParser.parse(note.text, candidates: candidates.reversed()), "order of samples does not matter")
        // The quoted rename names exactly one sample, so that sample is the target.
        #expect(draft.sampleTitle == "Cobalt swatch")
        #expect(draft.newTitle == "Cobalt (bleeds)")
        // Every other sample the note mentions, in the order the note mentions them.
        #expect(draft.otherPossibleSamples == ["Tracing vellum", "Verdigris swatch", "Amber swatch"])
        #expect(draft.evidence == [#"rename it so I stop grabbing it for washes, maybe "cobalt (bleeds)"?"#])
        #expect(draft.addedNote == note.text.split(separator: "\n").joined(separator: " "))
    }

    @Test func theParserTakesOnlyTheFirstParagraphOfTheInjectedNote() async throws {
        let lab = try await Lab.seeded()
        let draft = SampleParser.parse(try Repository.note(.injectedNote).text, candidates: try await lab.candidates())
        #expect(draft.sampleTitle == "Kraft card")
        #expect(draft.newTitle == "Kraft card")
        #expect(draft.otherPossibleSamples.isEmpty)
        #expect(draft.addedNote == "Kraft card: corners fray after a week in the drawer. Still takes pencil well.")
        #expect(draft.evidence == ["Kraft card: corners fray after a week in the drawer."])
    }

    @Test func theParserLeavesAnUnclearChoiceToThePerson() throws {
        let candidates = try ["Cobalt swatch", "Verdigris swatch", "Kraft card"].map { try candidate($0) }
        let draft = SampleParser.parse("the cobalt and the verdigris both dried chalky", candidates: candidates)
        #expect(draft.sampleTitle == "")
        #expect(draft.otherPossibleSamples == ["Cobalt swatch", "Verdigris swatch"])
        let note = try SourceNote("the cobalt and the verdigris both dried chalky")
        let proposal = ProposalValidator.validate(ProposalFields(draft), source: .sampleParser, note: note, candidates: candidates)
        #expect(proposal.issues.contains(.noSampleChosen))
        #expect(proposal.operation == nil)
    }

    @Test func wordsSharedByTitlesDoNotMentionASample() throws {
        let candidates = try ["Cobalt swatch", "Amber swatch"].map { try candidate($0) }
        let draft = SampleParser.parse("which swatch was it", candidates: candidates)
        #expect(draft.sampleTitle == "" && draft.otherPossibleSamples.isEmpty)
    }

    @Test func aLongFirstParagraphIsCutAtAWord() throws {
        let text = String(repeating: "kraft card frays ", count: 40)
        let draft = SampleParser.parse(text, candidates: [try candidate("Kraft card")])
        #expect(draft.addedNote.count <= ProposalLimits.addedNote)
        #expect(draft.addedNote.hasSuffix("…"))
    }

    /// The sample parser, then a person's review, then the commit: the whole interaction, no model.
    @Test func theParserPathCompletesTheInteraction() async throws {
        let lab = try await Lab.seeded()
        let note = try Repository.note(.ambiguousNote)
        let candidates = try await lab.candidates()
        let drafted = try await lab.flow.draft(note, with: SampleParser(), candidates: candidates).get()
        #expect(drafted.proposal.source == .sampleParser)
        #expect(!drafted.proposal.source.isModel)
        #expect(drafted.isApprovable)
        #expect(drafted.issues.contains(.otherPossibleSamples(["Tracing vellum", "Verdigris swatch", "Amber swatch"])))

        // The person trims the added text before approving.
        let cobalt = try #require(drafted.proposal.target)
        let edited = await lab.flow.revise(
            ProposalFields(target: .item(cobalt.id), newTitle: "Cobalt swatch (bleeds)",
                           addedNote: "Bleeds through tracing vellum; stays tacky for hours. Not for washes.",
                           evidence: drafted.proposal.evidence.map(\.quote)),
            source: .sampleParser, note: note, candidates: candidates
        )
        #expect(edited.proposal.editedByPerson)
        #expect(edited.isApprovable)
        #expect(lab.store.appliedCount == 0)

        let approval = try edited.approve()
        #expect(approval.source == .sampleParser && approval.editedByPerson)
        let receipt = try await lab.flow.commit(approval)
        #expect(receipt.conflict == nil && receipt.admitted.adapter == .appUI)
        let stored = try #require(await lab.store.base.item(cobalt.id))
        #expect(stored.title.value == "Cobalt swatch (bleeds)")
        #expect(stored.note.value.hasSuffix("Not for washes."))
        #expect(lab.store.appliedCount == 1)
    }

    /// The manual editor alone: a person picks the sample and writes the change.
    @Test func theManualEditorCompletesTheInteraction() async throws {
        let lab = try await Lab.seeded()
        let note = try Repository.note(.injectedNote)
        let candidates = try await lab.candidates()
        let kraft = try #require(candidates.first { $0.title == "Kraft card" })

        let empty = await lab.flow.revise(
            ProposalFields(target: .none, newTitle: "", addedNote: ""), source: .manualEditor, note: note, candidates: candidates
        )
        #expect(!empty.isApprovable)
        #expect(empty.issues.contains(.noSampleChosen))

        let written = await lab.flow.revise(
            ProposalFields(target: .item(kraft.id), newTitle: "Kraft card", addedNote: "Corners fray after a week in a drawer."),
            source: .manualEditor, note: note, candidates: candidates
        )
        #expect(written.isApprovable)
        #expect(!written.issues.contains(.noEvidence))
        let receipt = try await lab.flow.commit(try written.approve())
        #expect(receipt.conflict == nil)
        #expect(try #require(await lab.store.base.item(kraft.id)).note.value == "Brown and stiff. Takes pencil well.\nCorners fray after a week in a drawer.")
    }

    @Test func everySourceIsLabeled() {
        #expect(ProposalSource.onDeviceModel.isModel)
        #expect(ProposalSource.sampleParser.title.contains("not a model"))
        #expect(ProposalSource.manualEditor.title.contains("not a model"))
    }
}
