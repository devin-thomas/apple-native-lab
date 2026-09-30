import CryptoKit
import Foundation
@testable import LabDemo
import LabDomain
import LabStore
import LabSupport
import Testing

/// `Fixtures/showcase/typed-intelligence/`: LAB-010's fixture interaction, replayed from a clean
/// store. Its two edits are the sample parser's drafts of the two original notes, approved
/// unedited; `TypedIntelligenceQualificationTests` in `Packages/LabFeatures` checks that the real
/// flow drafts exactly these operations.
enum TypedIntelligenceShowcase {
    static let folder = Showcase.fixtures.appending(path: "typed-intelligence", directoryHint: .isDirectory)
    /// The seed the app bundles and seeds its first run with.
    static let appSeed = Showcase.repositoryRoot.appending(path: "Fixtures/demo/seed.json")

    static func script() throws -> DemoScript {
        try DemoScript(folder: folder)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: name))
    }

    static let cobalt = ItemID(rawValue: UUID(uuidString: "9B97BF2F-4D0B-4197-9CA8-36489DF40455")!)
    static let verdigris = ItemID(rawValue: UUID(uuidString: "3A1711A8-E1DB-489E-8321-414266A8DF49")!)
    static let kraft = ItemID(rawValue: UUID(uuidString: "6E2CED9D-B946-4188-8417-2E85C6A7268C")!)

    /// A copy of the showcase folder with its script changed, for tests that need a variant.
    static func variant(in temporary: TemporaryFolder, _ change: (inout [String: Any]) -> Void) throws -> URL {
        let copy = temporary.url.appending(path: "typed-intelligence", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: folder, to: copy)
        try rewriteScript(in: copy, change)
        return copy
    }
}

/// LAB-010-B step 1: replay the fixture interaction from a clean state. Fixture path: the replay
/// proves the operations an approved proposal becomes, not a model, a view, or a device.
@Suite struct TypedIntelligenceShowcaseTests {
    @Test func theShowcaseSeedIsTheAppsDemoSeedByteForByte() throws {
        #expect(try TypedIntelligenceShowcase.data("seed.json") == (try Data(contentsOf: TypedIntelligenceShowcase.appSeed)))
    }

    @Test func theShowcaseLoadsWithTheHashesOfItsExactBytes() throws {
        let script = try TypedIntelligenceShowcase.script()
        func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        #expect(script.subject == "LAB-010")
        #expect(script.dataTier == .publicFixture)
        #expect(script.seed.collections.count == 3 && script.seed.items.count == 12)
        #expect(script.inputs.map(\.reference) == [
            "script:typed-intelligence@sha256:\(hex(try TypedIntelligenceShowcase.data("script.json")))",
            "seed:typed-intelligence@sha256:\(hex(try Data(contentsOf: TypedIntelligenceShowcase.appSeed)))",
        ])
    }

    @Test func theInteractionPassesFromACleanStoreAndResetRestoresOnlyTheEditedSample() async throws {
        let run = await DemoRunner(store: .temporarySQLite).run(try TypedIntelligenceShowcase.script())
        checkStepInvariants(run)
        #expect(run.result == .passed, "\(run.outcome.summary)")
        #expect(run.steps.count == 13)

        // Each applied change is one update, committed as the app UI, offering its undo.
        for step in ["apply-cobalt", "apply-kraft"] {
            let receipt = try #require(run.steps.first { $0.id == name(step) }?.receipt)
            #expect(receipt.admitted.adapter == .appUI)
            #expect(receipt.admitted.operation.kind == .updateItem)
            #expect(receipt.changes.count == 1)
            #expect(receipt.undo != nil)
        }
        let kraftChange = try #require(run.steps.first { $0.id == name("apply-kraft") }?.receipt)
        #expect(kraftChange.changes.map(\.entity) == [.item(TypedIntelligenceShowcase.kraft)])

        let state = try #require(run.finalState)
        #expect(state.collections.count == 3 && state.items.count == 12)
        #expect(state.items.allSatisfy { $0.namespace == .demo && !$0.isArchived })
        let cobalt = try #require(state.items.first { $0.id == TypedIntelligenceShowcase.cobalt })
        #expect(cobalt.title.value == "Cobalt swatch")
        #expect(cobalt.note.value == "Deep cool blue. Pairs with the amber swatch.")
        #expect(cobalt.revision.rawValue == 3, "applied, then undone at its next revision")
        let kraft = try #require(state.items.first { $0.id == TypedIntelligenceShowcase.kraft })
        #expect(kraft.note.value == "Brown and stiff. Takes pencil well.")
        #expect(kraft.revision.rawValue == 3, "applied, then restored by Reset Demo at its next revision")

        // The second Reset Demo restored only the sample that still differed from the seed.
        let reset = try #require(run.steps.first { $0.id == name("reset-again") }?.receipt)
        #expect(reset.changes.map(\.entity) == [.item(TypedIntelligenceShowcase.kraft)])
        #expect(reset.removed.isEmpty)
    }

    @Test func replaysShareOneFingerprintAcrossRunsAndStores() async throws {
        let script = try TypedIntelligenceShowcase.script()
        let first = await DemoRunner(store: .temporarySQLite).run(script)
        let second = await DemoRunner(store: .temporarySQLite, clock: SuspendingIntervalClock()).run(script)
        let inMemory = await DemoRunner.manual().run(script)
        #expect(first.result == .passed && second.result == .passed && inMemory.result == .passed)
        #expect(ReplayComparison(first, second) == .identical(fingerprint: first.replayFingerprint))
        #expect(ReplayComparison(first, inMemory).isIdentical)
        #expect(first.id != second.id)
    }

    /// Denial: composed as the model-tool adapter, the proposer's adapter, the runner can change
    /// nothing. Its first approval asks for a grant outside the model tool's ceiling, the ledger
    /// refuses, and every later step is skipped, so the store stays empty.
    @Test func asTheModelToolAdapterTheReplayWritesNothing() async throws {
        let run = await DemoRunner.manual(adapter: .modelTool).run(try TypedIntelligenceShowcase.script())
        checkStepInvariants(run)
        #expect(run.result == .failed)
        let approval = try #require(run.steps.first)
        #expect(approval.id == name("approve-reset") && approval.result == .failed)
        #expect(approval.outcome.detail.contains("outside the adapter's ceiling"), "\(approval.outcome.detail)")
        #expect(run.steps.dropFirst().allSatisfy { $0.disposition == .skipped && $0.receipt == nil })
        let state = try #require(run.finalState)
        #expect(state.collections.isEmpty && state.items.isEmpty)
    }

    /// Denial of the change itself: the same edit submitted as the model tool after an app-UI
    /// reset is refused by the service, because commit is outside the model tool's ceiling.
    @Test func theModelToolCannotCommitTheShowcasesEdit() async throws {
        let script = try TypedIntelligenceShowcase.script()
        let store = InMemoryOperationStore()
        let service = OperationService(store: store)
        let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
        _ = try await service.perform(OperationRequest(id: RequestID(), operation: .resetDemo(seed: script.seed), actor: appUI))
        guard case .perform(_, .domain(let edit))? = script.steps.first(where: { $0.id == name("apply-cobalt") })?.action else {
            Issue.record("apply-cobalt is not a domain operation")
            return
        }
        let proposer = ActorScope(adapter: .modelTool, grants: [.read, .propose])
        await #expect(throws: OperationError.self) {
            _ = try await service.perform(OperationRequest(id: RequestID(), operation: edit, actor: proposer))
        }
        let proposal = try await service.propose(edit, as: proposer)
        #expect(proposal.isReady && proposal.proposedBy == .modelTool, "the proposer may propose it")
        #expect(await store.item(TypedIntelligenceShowcase.cobalt)?.revision == .initial, "and nothing was written")
    }

    /// Stale state: an approval made against an older revision records a conflict and overwrites
    /// nothing. The replay stops there.
    @Test func aStaleApplyRecordsAConflictAndChangesNothing() async throws {
        let temporary = try TemporaryFolder()
        let folder = try TypedIntelligenceShowcase.variant(in: temporary) { object in
            var steps = object["steps"] as? [[String: Any]] ?? []
            for index in steps.indices where steps[index]["id"] as? String == "apply-cobalt" {
                var update = steps[index]["updateItem"] as? [String: Any] ?? [:]
                update["expected"] = 2
                steps[index]["updateItem"] = update
            }
            object["steps"] = steps
        }
        let run = await DemoRunner.manual().run(try DemoScript(folder: folder))
        checkStepInvariants(run)
        #expect(run.result == .failed)
        let apply = try #require(run.steps.first { $0.id == name("apply-cobalt") })
        #expect(apply.result == .failed)
        #expect(apply.receipt?.conflict != nil)
        #expect(apply.outcome.detail.hasPrefix("Conflict, nothing changed"))
        let cobalt = try #require(run.finalState?.items.first { $0.id == TypedIntelligenceShowcase.cobalt })
        #expect(cobalt.revision == .initial && cobalt.title.value == "Cobalt swatch")
    }

    /// Cancellation: a replay cancelled after the lookup applies nothing.
    @Test func aCancelledReplayAppliesNothingAfterTheCancel() async throws {
        let run = await Task {
            await DemoRunner.manual().run(try! TypedIntelligenceShowcase.script()) { record in
                if record.id == name("find-blue") { cancelCurrentTask() }
            }
        }.value
        checkStepInvariants(run)
        #expect(run.result == .notRun)
        let index = try #require(run.steps.firstIndex { $0.id == name("find-blue") })
        #expect(run.steps[...index].allSatisfy { $0.result == .passed })
        #expect(run.steps[(index + 1)...].allSatisfy { $0.disposition == .cancelled && $0.result == .notRun })
        let state = try #require(run.finalState)
        #expect(state.items.allSatisfy { $0.revision == .initial })
    }
}

/// The LAB-010 evidence export: the showcase replayed twice as the app UI on SQLite with the
/// continuous clock, then exported through the rights and privacy review, together with the
/// records the other LAB-010-B runs produced.
///
/// It writes into a temporary folder that is removed afterwards. To keep the export, name a folder
/// and the build facts; with a folder named, every build fact is required:
///
///     LAB_DEMO_EVIDENCE_DIR=<folder> LAB_SOURCE_REVISION=<sha> LAB_SDK_NAME=macosx27.0 \
///     LAB_XCODE_VERSION=27.0 LAB_XCODE_BUILD=27A266a \
///     swift test --package-path Packages/LabDemo --filter TypedIntelligenceShowcaseEvidence
///
/// `LAB_EXTRA_EVIDENCE_RECORDS=<file>,<file>` adds records made elsewhere, so they pass the same
/// review: the hosted Mac test `TypedIntelligenceHostEvidenceTests` (exported from its result
/// bundle) and `LiveModelEvidenceTests` in `Packages/LabFeatures`. Each must decode as an
/// `EvidenceRecord` for LAB-010 from the same source revision. It keeps its file name.
///
/// Keep the export outside `evidence/`, and copy its `records/*.json` into `evidence/LAB-010/`.
@Suite struct TypedIntelligenceShowcaseEvidence {
    @Test func theShowcaseExportsEndToEnd() async throws {
        let environment = ProcessInfo.processInfo.environment
        let keep = environment["LAB_DEMO_EVIDENCE_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
        let facts = ["LAB_SOURCE_REVISION", "LAB_SDK_NAME", "LAB_XCODE_VERSION", "LAB_XCODE_BUILD"]
        if keep != nil {
            for fact in facts {
                try #require(environment[fact].map { !$0.isEmpty } == true, "a kept export names \(fact)")
            }
        }
        let provenance = BuildProvenance(
            sourceRevision: environment["LAB_SOURCE_REVISION"] ?? "unknown",
            sdkName: environment["LAB_SDK_NAME"] ?? "unknown",
            xcodeVersion: environment["LAB_XCODE_VERSION"] ?? "unknown",
            xcodeBuild: environment["LAB_XCODE_BUILD"] ?? "unknown"
        )
        var extraArtifacts: [ExportArtifact] = []
        let extraPaths = (environment["LAB_EXTRA_EVIDENCE_RECORDS"] ?? "").split(separator: ",").map(String.init)
        for path in extraPaths {
            let url = URL(filePath: path)
            let record = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: url))
            try #require(record.subject == "LAB-010")
            try #require(record.provenance.sourceRevision == provenance.sourceRevision, "one source revision per export")
            extraArtifacts.append(try .record(record, at: "records/\(url.lastPathComponent)", tier: .publicFixture))
        }

        let script = try TypedIntelligenceShowcase.script()
        let runner = DemoRunner(adapter: .appUI, store: .temporarySQLite)
        let runs = [await runner.run(script), await runner.run(script)]
        for run in runs { checkStepInvariants(run) }

        // Nothing is recorded unless the replays passed and agree.
        try #require(runs.allSatisfy { $0.result == .passed })
        try #require(ReplayComparison(runs[0], runs[1]).isIdentical)

        let record = try runs[0].evidenceRecord(
            provenance: provenance,
            check: "Typed Local Intelligence showcase replayed twice from a clean SQLite store as the app-UI adapter: the sample parser's reviewed drafts of both notes, an undo, and Reset Demo; both replays share one fingerprint"
        )
        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "LAB-010 Typed Local Intelligence showcase replay",
            artifacts: [
                try .run(runs[0], at: "runs/app-ui-first.json"),
                try .run(runs[1], at: "runs/app-ui-second.json"),
                try .record(record, at: "records/typed-intelligence-showcase-app-ui.json", tier: .publicFixture),
                try .file("typed-intelligence/script.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/script.json"),
                try .file("typed-intelligence/seed.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/seed.json"),
            ] + extraArtifacts,
            untested: [
                "The on-device model on a physical iPhone or iPad: no device was used.",
                "A device where the model is really unavailable: the Mac and the iOS simulator both report it available.",
            ],
            provenance: provenance
        ))
        #expect(preview.result == .passed)
        #expect(preview.refused.isEmpty)
        #expect(preview.reviews.count == 5 + extraArtifacts.count)
        #expect(preview.reviews.allSatisfy { $0.tier == .publicFixture && $0.decision == .approved })
        let records = 1 + extraArtifacts.count
        #expect(preview.summaryText.hasPrefix("Passed: 2 demo runs and \(records) evidence \(records == 1 ? "record" : "records") exported; every one passed."))

        let temporary = try TemporaryFolder()
        let written = try preview.write(into: keep ?? temporary.url, folderName: "lab-010-typed-intelligence-showcase")
        #expect(temporary.files(below: written) == Set(preview.files.map(\.path)))
        let stored = try JSONDecoder().decode(
            EvidenceRecord.self, from: Data(contentsOf: written.appending(path: "records/typed-intelligence-showcase-app-ui.json"))
        )
        #expect(stored == record)
        #expect(stored.subject == "LAB-010")
        #expect(stored.path == .fixture)
        #expect(stored.supportedState == .implemented, "a replay never supports device-verified")
        #expect(stored.inputs == script.inputs.map(\.reference))
        #expect(stored.limitations.first == DemoRun.fixtureLimitation)
        #expect(record.outcome.detail.contains("Adapter app-ui"))
    }
}
