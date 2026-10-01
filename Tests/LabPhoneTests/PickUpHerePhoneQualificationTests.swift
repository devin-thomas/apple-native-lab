import Foundation
import LabDomain
import PickUpHere
import Testing
@testable import NativeLab

/// Fixture replay through the iPhone session and fresh SQLite stores. No Handoff delivery or
/// clipboard transfer is performed; the explicit copy is passed in process.
@MainActor
@Suite struct PickUpHerePhoneQualificationTests {
    private func library() async throws -> LabLibrary {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PickUpQualification-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    @Test func aCleanDestinationImportsOnceResumesAndKeepsTheDraftAcrossReset() async throws {
        let source = try await library()
        let sender = PickUpSession()
        await sender.addSample(source)
        let offer = try #require(await sender.prepare(source))
        #expect(offer.document.sections == SampleDraft.sections)
        let destination = try await library()
        let receiver = PickUpSession()
        receiver.linkText = offer.link.absoluteString
        await receiver.resumeLink(destination)
        #expect(receiver.decision?.resumed == nil)
        #expect(receiver.decision?.revealedText.isEmpty == true)
        #expect(receiver.message?.contains("Import the document") == true)
        receiver.documentText = offer.document.text
        await receiver.importPastedDocument(destination)
        #expect(receiver.decision?.resumed?.sectionText == SampleDraft.sections[1])
        #expect(receiver.item(SampleDraft.documentID)?.namespace == .user)
        #expect(destination.latestReceipt?.receipt.admitted.adapter == .appUI)
        let receipts = destination.receipts.count
        await receiver.importPastedDocument(destination)
        #expect(destination.receipts.count == receipts)
        receiver.clear()
        #expect(receiver.decision == nil && receiver.offer == nil && !receiver.isAdvertising)
        #expect(receiver.linkText.isEmpty && receiver.documentText.isEmpty)
        #expect(await destination.resetDemo() != nil)
        await receiver.load(destination)
        #expect(receiver.item(SampleDraft.documentID)?.note.value == SampleDraft.note)
        #expect(receiver.items.filter { $0.id == SampleDraft.documentID }.count == 1)
    }

    @Test func revocationClearsTheOfferAndAChangedDraftClampsTheHint() async throws {
        let lab = try await library()
        let session = PickUpSession()
        await session.addSample(lab)
        let offer = try #require(await session.prepare(lab))
        session.linkText = offer.link.absoluteString
        await session.resumeLink(lab)
        #expect(session.decision?.resumed != nil)
        session.revokeSelected()
        #expect(session.offer == nil && !session.isAdvertising)
        #expect(session.decision?.revealedText.isEmpty == true)
        await session.resumeLink(lab)
        #expect(session.decision?.revealedText.isEmpty == true)
        #expect(await session.prepare(lab) == nil)
        session.allowSelected()
        #expect(session.decision == nil)
        let item = try #require(session.item(SampleDraft.documentID))
        _ = try await lab.submit(
            .updateItem(id: item.id, expected: item.revision, changes: ItemChanges(note: ItemNote("Only the opening remains."))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        await session.resumeLink(lab)
        let resumed = try #require(session.decision?.resumed)
        #expect(resumed.clamped && resumed.newerRevision)
        #expect(resumed.section == 0 && resumed.requestedSection == 1)
        #expect(resumed.sectionText == "Only the opening remains.")
        session.linkText = "nativelab://continue?note=unapproved"
        await session.resumeLink(lab)
        #expect(session.decision == nil)
        #expect(session.message == PickUpError.invalidPayload.sentence)
    }
}
