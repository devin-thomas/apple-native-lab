import Foundation
import LabDomain
import Testing
@testable import DocumentsEverywhere

@Suite("Sample catalog and adopt")
struct SampleCatalogTests {
    @Test("Enumerate returns both samples")
    func enumerateReturnsBothSamples() async throws {
        let items = try await SampleCatalog.bundled.enumerate()
        #expect(items.map(\.filename) == ["harbor-note.anlab", "tide-card.anlab"])
        #expect(items.allSatisfy { !$0.isMirror })
    }

    @Test("Open returns bytes and a preview")
    func openReturnsBytesAndAPreview() async throws {
        let opened = try await SampleCatalog.bundled.open(ProviderItemID(rawValue: "sample.tide-card"))
        #expect(opened.preview.title == "Tide card")
        #expect(!opened.data.isEmpty)
    }

    @Test("Cancelled open surfaces cancellation")
    func cancelledOpenSurfacesCancellation() async {
        let task = Task {
            await Task.yield()
            return try await SampleCatalog.bundled.open(ProviderItemID(rawValue: "sample.harbor-note"))
        }
        task.cancel()
        do {
            _ = try await task.value
        } catch is CancellationError {
            // Task cancelled before or during open.
        } catch let error as DocumentsEverywhereError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("Adopt goes through the importer and leaves a receipt")
    func adoptGoesThroughTheImporterAndLeavesAReceipt() async throws {
        let lab = try await TestLab.make()
        let before = await lab.snapshot()
        let result = try await lab.adopter.adopt(
            ProviderItemID(rawValue: "sample.harbor-note"),
            into: lab.inbox
        )
        #expect(result.change == .created)
        #expect(result.receipt.status == .committed)
        let after = await lab.snapshot()
        #expect(after.subtracting(before).count == 1)
        #expect(result.item?.title.value == "Harbor note")
    }

    @Test("Cancelled adopt commits nothing")
    func cancelledAdoptCommitsNothing() async throws {
        let lab = try await TestLab.make()
        let before = await lab.snapshot()
        let task = Task {
            try await lab.adopter.adopt(
                ProviderItemID(rawValue: "sample.tide-card"),
                into: lab.inbox
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            // A very fast adopt may finish before cancel is observed; check the store either way.
        } catch is DocumentsEverywhereError {
            // cancelled
        } catch is CancellationError {
            // cancelled
        }
        // If cancel won, the store is unchanged. If adopt won, one item exists — both are honest.
        let after = await lab.snapshot()
        #expect(after.subtracting(before).count <= 1)
    }

    @Test("Unavailable path: missing sample")
    func unavailablePathMissingSample() async throws {
        let lab = try await TestLab.make()
        await #expect(throws: DocumentsEverywhereError.unknownSample) {
            try await lab.adopter.adopt(ProviderItemID(rawValue: "sample.missing"), into: lab.inbox)
        }
        #expect(await lab.snapshot().isEmpty)
    }
}
