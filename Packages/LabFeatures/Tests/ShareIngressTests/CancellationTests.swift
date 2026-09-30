import Foundation
import LabDomain
import LabStaging
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import ShareIngress

/// LAB-007: cloud-backed and slow attachments can be cancelled safely. A cancelled intake keeps
/// nothing it staged, leaves no partial file, and never blocks the next intake.
@Suite struct CancellationTests {
    @Test func cancellingWhileACloudBackedAttachmentDownloadsKeepsNothing() async throws {
        let lab = try Station()
        let gate = ProviderGate()
        let sources = ItemProviderAttachment.attachments(from: [
            Providers.text("Staged before the slow one"),
            Providers.slowFile(gate),
            Providers.text("Never reached"),
        ])
        let station = lab.shareStation
        let intake = Task { await station.receive(sources, via: .shareExtension) }
        await gate.waitUntilStarted()
        // The first attachment is already staged while the second is still "downloading".
        #expect(await lab.shared.staging.waitingImports().count == 1)

        intake.cancel()
        let report = await intake.value
        #expect(report.wasCancelled)
        #expect(report.outcomes.map(\.result) == [.cancelled, .cancelled, .cancelled])
        #expect(report.summary == "The import was cancelled. Nothing from it was kept.")
        for _ in 0..<100 where !gate.wasCancelled { try await Task.sleep(for: .milliseconds(10)) }
        #expect(gate.wasCancelled, "the provider's progress was cancelled")

        // Nothing waits, nothing is half-written, and the scratch copy folder is gone.
        #expect(await lab.shared.staging.waitingImports().isEmpty)
        #expect(lab.leftovers(in: lab.shared, "incoming").isEmpty)
        #expect(await lab.inbox.snapshot() == InboxSnapshot(entries: [], quarantined: [], sources: [.host, .shareExtension]))
        let scratch = FileManager.default.temporaryDirectory.appending(path: "ShareIngress-\(report.batch)")
        #expect(!FileManager.default.fileExists(atPath: scratch.path(percentEncoded: false)))

        // The download finishing late copies nothing.
        let late = lab.folder.appending(path: "late.jpeg")
        try SyntheticMedia.bytes(128).write(to: late)
        gate.release(with: late)
        #expect(await lab.shared.staging.waitingImports().isEmpty)

        // The next intake is unaffected.
        let next = await station.receive(ItemProviderAttachment.attachments(from: [Providers.text("Next share")]), via: .shareExtension)
        #expect(next.stagedCount == 1)
    }

    @Test func cancellingWhileBytesStreamLeavesNoPartialFile() async throws {
        let lab = try Station()
        let started = ProviderGate()
        let station = lab.hostStation
        let intake = Task {
            await station.receive([TricklingFile(chunks: 500, chunkSize: 4_096, started: started)], via: .filePicker)
        }
        await started.waitUntilStarted()
        intake.cancel()
        let report = await intake.value
        #expect(report.wasCancelled)
        #expect(await lab.host.staging.waitingImports().isEmpty)
        #expect(lab.leftovers(in: lab.host, "incoming").isEmpty)
        #expect(lab.leftovers(in: lab.host, "pending").isEmpty)

        let next = await station.receive(ItemProviderAttachment.attachments(from: [Providers.text("After a cancel")]), via: .paste)
        #expect(next.stagedCount == 1)
    }

    @Test func aDuplicateThatWasWaitingBeforeACancelledIntakeStaysWaiting() async throws {
        let lab = try Station()
        let station = lab.shareStation
        let earlier = await station.receive(ItemProviderAttachment.attachments(from: [Providers.text("Kept note")]), via: .shareExtension)
        let gate = ProviderGate()
        let intake = Task {
            await station.receive(
                ItemProviderAttachment.attachments(from: [Providers.text("Kept note"), Providers.slowFile(gate)]), via: .shareExtension
            )
        }
        await gate.waitUntilStarted()
        intake.cancel()
        #expect(await intake.value.wasCancelled)
        let entries = await lab.inbox.snapshot().entries
        #expect(entries.map(\.id.staging) == earlier.waitingIDs)
        #expect(entries.first?.origin?.batch == earlier.batch)
    }

    @Test func aLoadCancelledBeforeItsCallbackResumesOnceAndRunsNothingLate() async throws {
        let gate = LoadGate<Int>()
        let ran = Mutex(false)
        let result: Result<Int, ImportRejection> = await withCheckedContinuation { continuation in
            gate.begin(continuation)
            gate.cancel()
            // The provider's callback arrives after the cancellation.
            gate.finish { () throws(ImportRejection) -> Int in
                ran.withLock { $0 = true }
                return 1
            }
        }
        #expect(result == .failure(.cancelled))
        #expect(ran.withLock { $0 } == false)
    }
}
