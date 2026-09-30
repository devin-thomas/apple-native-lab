#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import Foundation
import LabDomain
import Synchronization
import Testing
@testable import TypedIntelligence

/// The real on-device model on both fixtures. Opt-in, because it needs an eligible device with
/// Apple Intelligence on and the model ready, and its output is the model's, not a fixed answer:
///
///     LAB_LIVE_MODEL=1 LAB_LIVE_MODEL_OUTPUT=/path/record.json swift test --filter LiveModelTests
///
/// Each fixture is drafted twice with greedy sampling. The test asserts only what the design
/// guarantees: a draft arrives within the limit, its sample is one of the offered titles, and the
/// store is untouched. Whether the draft is right is for the person reviewing it.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LAB_LIVE_MODEL"] == "1", "set LAB_LIVE_MODEL=1 to run the on-device model"))
struct LiveModelTests {
    /// Counts proposer reads, so tool calls show up: one read lists the samples, each further read
    /// during a draft is a `findSamples` call.
    final class CountingBackend: TypedIntelligenceBackend {
        let base: ServiceIntelligenceBackend
        private let reads = Mutex(0)
        init(_ base: ServiceIntelligenceBackend) { self.base = base }
        var readCount: Int { reads.withLock { $0 } }
        func items(_ filter: ItemFilter) async throws(IntelligenceError) -> [LabItem] {
            reads.withLock { $0 += 1 }
            return try await base.items(filter)
        }
        func propose(_ operation: DomainOperation) async throws(IntelligenceError) -> OperationProposal { try await base.propose(operation) }
        func commit(_ change: ApprovedChange) async throws(IntelligenceError) -> ActionReceipt { try await base.commit(change) }
    }

    @Test func theOnDeviceModelDraftsEachFixture() async throws {
        let unavailable = OnDeviceModelExtractor.unavailability()
        try #require(unavailable == nil, "the model is unavailable here: \(String(describing: unavailable))")
        var runs: [[String: Any]] = []
        for fixture in IntelligenceFixture.allCases {
            var drafts: [ProposalFields] = []
            for attempt in 1...2 {
                let lab = try await Lab.seeded()
                let backend = CountingBackend(lab.backend)
                let flow = TypedIntelligenceFlow(backend: backend, timeLimit: .seconds(60))
                let candidates = try await flow.candidates()
                let before = await lab.items()
                let readsBefore = backend.readCount
                let clock = ContinuousClock()
                let start = clock.now
                let result = await flow.draft(try Repository.note(fixture), with: OnDeviceModelExtractor(), candidates: candidates)
                let elapsed = clock.now - start
                let reviewable = try result.get()
                let proposal = reviewable.proposal
                #expect(proposal.target != nil, "guided generation keeps the sample to an offered title")
                #expect(elapsed < .seconds(60))
                #expect(lab.store.appliedCount == 0)
                #expect(await lab.items() == before)
                drafts.append(ProposalFields(
                    target: proposal.target.map { .title($0.title) } ?? .none, newTitle: proposal.newTitle,
                    addedNote: proposal.addedNote, evidence: proposal.evidence.map(\.quote),
                    otherPossibleSamples: proposal.otherPossibleSamples.map(\.title)))
                runs.append([
                    "fixture": fixture.fileName,
                    "attempt": attempt,
                    "milliseconds": Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000),
                    "lookupCalls": backend.readCount - readsBefore,
                    "sample": proposal.target?.title ?? "",
                    "otherPossibleSamples": proposal.otherPossibleSamples.map(\.title),
                    "newTitle": proposal.newTitle,
                    "addedNote": proposal.addedNote,
                    "evidenceKept": proposal.evidence.map(\.quote),
                    "issues": reviewable.issues.map(\.message),
                    "approvable": reviewable.isApprovable,
                    "serviceSummary": reviewable.serviceSummary ?? "",
                    "storeWrites": lab.store.appliedCount,
                ])
            }
            #expect(drafts.count == 2)
        }
        let record: [String: Any] = [
            "experiment": "LAB-010",
            "path": "live on-device model through swift test on the host Mac; fixture notes over the real demo seed in an in-memory store",
            "availability": "available",
            "supportsCurrentLocale": true,
            "locale": Locale.current.identifier,
            "variant": OnDeviceModelExtractor.variantName ?? "not reported",
            "sampling": "greedy, maximumResponseTokens 512",
            "runs": runs,
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        if let path = ProcessInfo.processInfo.environment["LAB_LIVE_MODEL_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: path))
        }
    }
}
#endif
