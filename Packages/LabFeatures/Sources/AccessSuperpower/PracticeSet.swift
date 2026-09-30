import Foundation
import LabDomain

/// The experiment's own fixture state: which demo samples to archive so the chart has something to
/// compare. The first run of the seed archives nothing, so without this the task has no answer.
///
/// Setting it up archives each listed sample through the operation service, one receipt each, and
/// only when a person presses the control. Resetting it restores only the listed samples that are
/// still archived. Nothing else in the demo, and nothing in a person's own data, is touched.
/// The same IDs are stated in `Fixtures/access/archive-chart.json`, and a test keeps the two equal.
public struct PracticeSet: Hashable, Sendable {
    /// Demo sample IDs from `Fixtures/demo/seed.json`, in the order they are archived.
    public let sampleIDs: [ItemID]

    public init(sampleIDs: [ItemID]) {
        self.sampleIDs = sampleIDs
    }

    /// Three mineral specimens, two pigment swatches, and one paper stock sample, so the answer is
    /// the middle bar rather than the first.
    public static let standard = PracticeSet(sampleIDs: [
        "AF451890-CA80-4DE9-B18B-4007066C9177", // Quartz point
        "D279FB0E-642E-463A-B3DA-299442A1C7CB", // Banded agate slice
        "C6468C0B-4BF6-48E8-AE5D-F5FC7A041097", // Obsidian flake
        "9B97BF2F-4D0B-4197-9CA8-36489DF40455", // Cobalt swatch
        "C8E1904C-E8DC-40A0-93D3-53F6C0FFF95D", // Ochre swatch
        "6933AC83-9E61-4264-8EB8-0535B3C5E0F8", // Tracing vellum
    ].map { ItemID(rawValue: UUID(uuidString: $0)!) })

    /// Archives for the listed samples that are present and not archived, in list order.
    public func setUpOperations(in tally: ArchiveTally) -> [DomainOperation] {
        present(in: tally).filter { !$0.isArchived }.map { .archiveItem(id: $0.id, expected: $0.revision) }
    }

    /// Restores for the listed samples that are still archived, in list order.
    public func resetOperations(in tally: ArchiveTally) -> [DomainOperation] {
        present(in: tally).filter(\.isArchived).map { .restoreItem(id: $0.id, expected: $0.revision) }
    }

    /// The listed samples the tally holds, in list order.
    private func present(in tally: ArchiveTally) -> [LabItem] {
        sampleIDs.compactMap { tally.sample($0)?.sample }
    }
}

/// Runs a practice set's operations one at a time and stops cleanly when cancelled.
///
/// Each operation is its own request with its own receipt, so a cancellation between two of them
/// leaves exactly the ones already committed, each with an undo, and Reset Practice restores them.
public enum PracticeRun {
    public struct Result: Sendable {
        public let receipts: [ActionReceipt]
        /// True when the run stopped before its last operation because its task was cancelled.
        public let wasCancelled: Bool
    }

    /// Runs on the caller's actor, so a host can commit through its main-actor library.
    public static func perform(
        _ operations: [DomainOperation],
        isolation: isolated (any Actor)? = #isolation,
        commit: (DomainOperation) async throws -> ActionReceipt
    ) async throws -> Result {
        var receipts: [ActionReceipt] = []
        for operation in operations {
            if Task.isCancelled { return Result(receipts: receipts, wasCancelled: true) }
            receipts.append(try await commit(operation))
        }
        return Result(receipts: receipts, wasCancelled: false)
    }

    /// One sentence for the result area and the announcement.
    public static func sentence(archiving: Bool, _ result: Result, of total: Int) -> String {
        let verb = archiving ? "Archived" : "Restored"
        let done = result.receipts.count
        let samples = done == 1 ? "1 practice sample" : "\(done) practice samples"
        if result.wasCancelled {
            return "Stopped after \(done) of \(total). \(verb) \(samples); each has its own receipt."
        }
        return done == 0 ? "Nothing to change." : "\(verb) \(samples). Each has its own receipt."
    }
}
