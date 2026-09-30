import Foundation
import LabDomain
import PortableObjects
import Testing
@testable import NativeLab

/// LAB-008-B step 3 in the sandboxed Mac host: two windows on one lab, a stale review, and Reset
/// Demo with a review open, through `PortableObjectsSession` and `LabLibrary` on fresh SQLite
/// stores. The app's windows share one staging folder, so these sessions do too.
@MainActor
@Suite struct PortableObjectsQualificationHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "PortableObjectsQualificationHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// A second window's session on the same library and staging folder.
    private func secondWindow(of lab: PortableHostLab) async -> PortableObjectsSession {
        let staging = lab.stagingRoot
        let session = PortableObjectsSession(locateStaging: { staging })
        await session.load(lab.library)
        return session
    }

    /// Duplicate state: two windows review the same new object and both press Import. The second
    /// press replays the first receipt, says so, and the lab holds one item.
    @Test func twoWindowsImportingOneObjectCommitItOnce() async throws {
        let lab = try await PortableHostLab.make("two-windows", in: folder)
        let other = await secondWindow(of: lab)
        await lab.session.openSample(library: lab.library)
        await other.openSample(library: lab.library)
        let first = try #require(await lab.session.commit(library: lab.library))
        let second = try #require(await other.commit(library: lab.library))
        #expect(second.receipt == first.receipt)
        #expect(other.outcome?.sentence == "This import had already been committed; its receipt is shown.")
        #expect(lab.library.receipts.filter { $0.receipt.requestID == first.receipt.requestID }.count == 1)
        await lab.session.load(lab.library)
        #expect(lab.session.entries.filter { $0.id == PortableHostLab.sampleID }.count == 1)
        #expect(lab.pendingStaged() == 0)
    }

    /// Finding, recorded as current behavior: the windows share one staged copy of the same bytes,
    /// so closing the review in one window withdraws it in the other. Its Import is refused with a
    /// sentence, and nothing is written.
    @Test func closingAReviewInOneWindowWithdrawsTheSameReviewInAnother() async throws {
        let lab = try await PortableHostLab.make("withdrawn", in: folder)
        let other = await secondWindow(of: lab)
        await lab.session.openSample(library: lab.library)
        await other.openSample(library: lab.library)
        await lab.session.closeReview()
        let receipts = lab.library.receipts.count
        #expect(await other.commit(library: lab.library) == nil)
        #expect(other.message?.hasPrefix("This import is no longer waiting.") == true)
        #expect(lab.library.receipts.count == receipts)
        await lab.session.load(lab.library)
        #expect(lab.session.entry(PortableHostLab.sampleID) == nil)
    }

    /// Stale state: the object changes in the lab while a changed copy is under review. Applying
    /// the copy is refused, the lab's change stands, and no receipt is added.
    @Test func aChangeInTheLabDuringTheReviewStopsTheImport() async throws {
        let lab = try await PortableHostLab.make("stale", in: folder)
        await lab.session.openSample(library: lab.library)
        _ = try #require(await lab.session.commit(library: lab.library))
        var changed = try LabDocument(decoding: try #require(PortableSample.data)).root
        changed["title"] = .string("Their title")
        let file = folder.appending(path: "changed.anlab")
        try LabDocument(validating: .object(changed)).encoded().write(to: file)
        await lab.session.open(fileAt: file, library: lab.library)
        #expect(lab.plan == "differs")

        _ = try await lab.library.submit(
            .updateItem(id: PortableHostLab.sampleID, expected: .initial, changes: ItemChanges(title: EntityTitle("My title"))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        let receipts = lab.library.receipts.count
        #expect(await lab.session.commit(library: lab.library) == nil)
        #expect(lab.session.message == PortableObjectError.stateChanged.userMessage)
        #expect(lab.library.receipts.count == receipts)
        #expect(lab.session.entry(PortableHostLab.sampleID)?.item.title.value == "My title")
    }

    /// Reset Demo with a review open: the review still imports the object as the person's own,
    /// and a second Reset Demo leaves it and its bytes alone.
    @Test func aReviewOpenAcrossResetDemoImportsAsYourOwn() async throws {
        let lab = try await PortableHostLab.make("reset", in: folder)
        await lab.session.openSample(library: lab.library)
        #expect(await lab.library.resetDemo() != nil)
        _ = try #require(await lab.session.commit(library: lab.library))
        #expect(await lab.library.resetDemo() != nil)
        await lab.session.load(lab.library)
        #expect(lab.session.entry(PortableHostLab.sampleID)?.item.namespace == .user)
        #expect(lab.session.exportPreview(for: PortableHostLab.sampleID)?.object.data == PortableSample.data)
    }
}
