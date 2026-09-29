import Foundation
import Testing
@testable import NativeLab

/// CORE-010: what assistive technology is told when a change lands, and the sentences that stand
/// in for data displays. The text is checked here; whether a screen reader speaks it is a manual
/// pass (docs/ACCESSIBILITY_REVIEW.md).
@MainActor
@Suite struct AnnouncementAndSummaryTests {
    let storeURL: URL

    init() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AnnouncementAndSummaryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appending(path: LabStoreLocation.fileName)
    }

    @Test func eachReceiptIsAnnouncedWithWhatChangedAndWhetherItCanBeUndone() async throws {
        let url = storeURL
        let library = LabLibrary(locateStore: { url })
        await library.start()
        let cobalt = try #require(library.collections.first?.items.dropFirst().first)
        let name = cobalt.title.value

        let archive = try #require(await library.setArchived(cobalt, true))
        let archived = try #require(LabAnnouncement.outcome(of: archive, in: library))
        #expect(archived.text == "Archived item “\(name)”. Undo is available.")
        #expect(archived.priority == .normal)

        let reset = try #require(await library.resetDemo())
        let resetAnnouncement = try #require(LabAnnouncement.outcome(of: reset, in: library))
        #expect(resetAnnouncement.text == "Reset the demo to its original 3 collections and 12 items: restored 1.")
        #expect(resetAnnouncement.priority == .normal)

        // The archive's undo is now stale: it is refused, and that interrupts.
        let stale = try #require(await library.undo(archive))
        let refused = try #require(LabAnnouncement.outcome(of: stale, in: library))
        #expect(refused.text == "Not applied because item “\(name)” changed: expected revision 2, found 3.")
        #expect(refused.priority == .high)
    }

    @Test func aFailureIsAnnouncedAndNothingIsAnnouncedWithoutAResult() async throws {
        let failure = LabAnnouncement(failure: "The change was not saved. Nothing was written.")
        #expect(failure.text == "The change was not saved. Nothing was written.")
        #expect(failure.priority == .high)

        let url = storeURL
        let library = LabLibrary(locateStore: { url })
        await library.start()
        #expect(LabAnnouncement.outcome(of: nil, in: library) == nil, "no receipt and no failure: nothing to say")
    }

    @Test func countSummariesReadAsOneSentence() {
        let parts = [CountSummary.Part(count: 1, label: "available"),
                     CountSummary.Part(count: 0, label: "declined"),
                     CountSummary.Part(count: 6, label: "unavailable")]
        #expect(CountSummary(total: 7, singular: "capability", plural: "capabilities", parts: parts).sentence
            == "7 capabilities: 1 available, 6 unavailable.")
        #expect(CountSummary(total: 1, singular: "capability", plural: "capabilities", parts: [.init(count: 1, label: "available")]).sentence
            == "1 capability: 1 available.")
        #expect(CountSummary(total: 0, singular: "capability", plural: "capabilities", parts: parts).sentence
            == "No capabilities.")
        #expect(CountSummary(total: 3, singular: "sample", plural: "samples", parts: []).sentence == "3 samples.")
    }

    @Test func theReadinessBoardSummarizesEveryProbe() async {
        let board = CapabilityBoard()
        let before = board.summary
        #expect(before.total == board.probed.count)
        #expect(before.sentence.hasSuffix("\(board.probed.count) still probing."), "\(before.sentence)")

        await board.refresh()
        let after = board.summary
        #expect(!after.sentence.contains("still probing"), "\(after.sentence)")
        #expect(after.parts.map(\.count).reduce(0, +) == board.probed.count)
    }
}
