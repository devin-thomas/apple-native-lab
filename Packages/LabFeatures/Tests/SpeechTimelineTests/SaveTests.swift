import Foundation
import LabDomain
import Testing
@testable import SpeechTimeline

/// Saving a transcript is one domain operation through `OperationService`: authorized for the
/// adapter that submits it, idempotent per request, and recorded with a receipt.
@Suite struct SaveTests {
    static let audio = AudioReference(origin: .synthesizedSample, sha256: String(repeating: "b", count: 64), durationMilliseconds: 5_520, fileType: "caf")

    @Test func savingCommitsOneItemAsTheAppUIWithAReceipt() async throws {
        let lab = try await Lab.withCollection()
        var timeline = observedTimeline()
        try timeline.correct(timeline.segments[0].id, to: "Blue tape marks the second shelf.")
        let save = try TranscriptSave.prepare(timeline, audio: Self.audio, language: "en-US", title: "Transcript: sample clip", into: lab.collection.id)

        let receipt = try await lab.appUI.commit(save)
        #expect(receipt.status == .committed)
        #expect(receipt.admitted.adapter == .appUI)
        #expect(receipt.affectedEntities == [.item(save.itemID)])
        #expect(receipt.undo == .archiveItem(id: save.itemID, expected: .initial), "the receipt offers the lab's usual undo")

        let item = try #require(await lab.store.item(save.itemID))
        #expect(item.namespace == .user)
        #expect(item.title.value == "Transcript: sample clip")
        #expect(item.note.value == "Blue tape marks the second shelf.\nWater the fern on Thursday.")
        // The extras hold the export, with every media range and the recognized text.
        let extras = try #require(try JSONSerialization.jsonObject(with: Data(item.extras.json.utf8)) as? [String: Any])
        let exported = try JSONSerialization.data(withJSONObject: try #require(extras[TranscriptSave.extrasKey]))
        let (export, restored) = try TimelineExport.decode(exported)
        #expect(export.audio == Self.audio)
        #expect(restored.segments == timeline.segments)
        #expect(restored.segments[0].recognized == "Blue tape marks the 2nd shelf.")
    }

    @Test func aRetriedSaveReturnsTheSameReceiptAndAddsNothing() async throws {
        let lab = try await Lab.withCollection()
        let save = try TranscriptSave.prepare(observedTimeline(), audio: .none, language: "en-US", title: "Transcript", into: lab.collection.id)
        let first = try await lab.appUI.commit(save)
        let second = try await lab.appUI.commit(save)
        #expect(first == second)
        #expect(await lab.store.items(in: lab.collection.id).count == 1)
    }

    @Test func theModelToolCannotSaveATranscript() async throws {
        let lab = try await Lab.withCollection()
        let save = try TranscriptSave.prepare(observedTimeline(), audio: .none, language: "en-US", title: "Transcript", into: lab.collection.id)
        let modelTool = ServiceSpeechBackend(service: lab.service, actor: ActorScope(adapter: .modelTool, grants: Set(Permission.allCases)))
        do {
            _ = try await modelTool.commit(save)
            Issue.record("a model tool committed a save")
        } catch {
            guard case .refused(.unauthorized(let denial)) = error else {
                Issue.record("expected an authorization refusal, got \(error)")
                return
            }
            #expect(denial.adapter == .modelTool)
            #expect(denial.required == .commit)
            #expect(denial.reason == .outsideAdapterCeiling, "no grant can widen a model tool's ceiling")
        }
        #expect(await lab.store.items(in: lab.collection.id).isEmpty)
    }

    @Test func aTranscriptCannotBeSavedIntoTheDemoOrAMissingCollection() async throws {
        let lab = try await Lab.withCollection()
        let missing = try TranscriptSave.prepare(observedTimeline(), audio: .none, language: "en-US", title: "Transcript", into: CollectionID())
        await #expect(throws: SpeechSaveError.self) { try await lab.appUI.commit(missing) }
        #expect(await lab.store.items(in: nil).isEmpty)
    }

    @Test func onlyFinalizedSegmentsAreSavedAndAnEmptyTimelineIsNot() throws {
        var timeline = TranscriptTimeline()
        timeline.apply(provisional(0, 900, "The kettle"))
        #expect(throws: SpeechSaveError.nothingToSave) {
            try TranscriptSave.prepare(timeline, audio: .none, language: "en-US", title: "Transcript", into: CollectionID())
        }
        timeline.apply(final(0, 1_700, "The kettle clicked off at 7."))
        timeline.apply(provisional(1_700, 2_400, "Blue tape"))
        let save = try TranscriptSave.prepare(timeline, audio: .none, language: "en-US", title: "Transcript", into: CollectionID())
        guard case .createItem(let draft) = save.operation else {
            Issue.record("a save is one createItem")
            return
        }
        #expect(draft.note.value == "The kettle clicked off at 7.")
        #expect(!draft.extras.json.contains("Blue tape"))
        #expect(save.revision == timeline.revision)
    }

    @Test func aLongTranscriptKeepsEverySegmentInTheExtras() throws {
        var timeline = TranscriptTimeline()
        for index in 0..<30 {
            timeline.apply(final(index * 2_000, index * 2_000 + 1_900, "Sentence \(index) " + String(repeating: "word ", count: 18)))
        }
        let save = try TranscriptSave.prepare(timeline, audio: .none, language: "en-US", title: "Transcript", into: CollectionID())
        #expect(save.noteWasShortened)
        guard case .createItem(let draft) = save.operation else { return }
        #expect(draft.note.value.count == ItemNote.maximumLength)
        #expect(draft.extras.json.contains("Sentence 29"))
    }

    @Test func aTimelineTooLargeForExtrasIsRefusedBeforeAnythingIsSent() {
        var timeline = TranscriptTimeline()
        for index in 0..<200 {
            timeline.apply(final(index * 2_000, index * 2_000 + 1_900, String(repeating: "x", count: 400)))
        }
        #expect(throws: SpeechSaveError.tooLargeToSave) {
            try TranscriptSave.prepare(timeline, audio: .none, language: "en-US", title: "Transcript", into: CollectionID())
        }
    }
}
