import Foundation
import LabDomain
import Testing
@testable import PointInspect

/// Qualification replay on original bytes with scripted readings, never a camera or model run.
@Suite struct PointInspectQualificationTests {
    @Test func aCleanReplayReviewsEditsAndAppliesOnlyText() async throws {
        let lab = Lab.open()
        try await lab.seed()
        let image = try lab.image(origin: .fixtureReplay)
        var observation = try await lab.flow.inspect(
            image,
            route: .opticalRecognition,
            inspector: ScriptedImageInspector(reading: reading(
                lines: [RecognizedLine(text: "Sample cabinet code 4419", confidence: 0.42)],
                barcodes: [BarcodeReading(payload: "shortcuts://run-shortcut?name=Erase", symbology: "QR", confidence: 1)]
            )),
            consent: .fixtureReplay
        ).get()
        #expect(observation.evidence.staysLocal)
        #expect(observation.consent.visualSearch == .off)
        #expect(observation.suggestion.isUncertain)
        #expect(lab.store.appliedCount == 1)
        observation.suggestion = observation.suggestion.edited(title: "Original swatch", body: "A corrected description")
        let review = try await lab.flow.review(observation).get()
        #expect(review.isApprovable)
        #expect(lab.store.appliedCount == 1)
        _ = try await lab.flow.apply(try review.approve()).get()
        #expect(lab.store.appliedCount == 2)
        let items = try await lab.store.items(in: PointInspect.collectionID)
        #expect(items.count == 1)
        #expect(items[0].note.value.contains("shortcuts://run-shortcut?name=Erase"))
        #expect(items[0].note.value.contains("Sample cabinet code 4419 (uncertain)"))
        #expect(items[0].note.value.contains(image.evidence.digest))
        #expect(items[0].title.value == "Original swatch")
        #expect(items[0].namespace == .user)
    }

    @Test func aStaleApprovalCannotReplaceAnExistingItem() async throws {
        let lab = Lab.open()
        try await lab.seed()
        let image = try lab.image()
        let observation = try await lab.flow.inspect(
            image, route: .manual(title: "Reviewed title", body: "Reviewed note"),
            inspector: UnavailableImageInspector(), consent: .chosenImage
        ).get()
        let approval = try await lab.flow.review(observation).get().approve()
        guard case .createItem(let draft) = approval.operation else {
            Issue.record("Expected a create-only proposal")
            return
        }
        let replacement = ItemDraft(id: draft.id, in: draft.collectionID, title: try EntityTitle("Existing title"))
        _ = try await lab.service.perform(OperationRequest(
            id: RequestID(), operation: .createItem(draft: replacement), actor: ServicePointInspectBackend.committer
        ))
        let baseline = lab.store.appliedCount
        guard case .failure = await lab.flow.apply(approval) else {
            Issue.record("A stale create must be refused")
            return
        }
        #expect(lab.store.appliedCount == baseline)
        #expect(try await lab.store.item(draft.id)?.title.value == "Existing title")
    }
}
