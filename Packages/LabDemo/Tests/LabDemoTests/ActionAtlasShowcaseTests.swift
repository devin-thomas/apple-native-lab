import CryptoKit
import Foundation
@testable import LabDemo
import LabDomain
import LabStore
import LabSupport
import Testing

/// `Fixtures/showcase/action-atlas/`: LAB-001's fixture interaction, replayed from a clean store.
enum ActionAtlasShowcase {
    static let folder = Showcase.fixtures.appending(path: "action-atlas", directoryHint: .isDirectory)
    /// The seed the app bundles and seeds its first run with.
    static let appSeed = Showcase.repositoryRoot.appending(path: "Fixtures/demo/seed.json")

    static func script() throws -> DemoScript {
        try DemoScript(folder: folder)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: name))
    }

    static let fieldNotes = CollectionID(rawValue: UUID(uuidString: "7EDF340E-5341-42F6-BE23-8B56F95106D8")!)
    static let graphite = ItemID(rawValue: UUID(uuidString: "45D11168-AE81-41D9-A9D1-BD40CA21A2E2")!)
    static let amber = ItemID(rawValue: UUID(uuidString: "DB666EF1-F642-43F1-B415-895B6ECFF693")!)

    /// A copy of the showcase folder with its script changed, for tests that need a variant.
    static func variant(in temporary: TemporaryFolder, _ change: (inout [String: Any]) -> Void) throws -> URL {
        let copy = temporary.url.appending(path: "action-atlas", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: folder, to: copy)
        try rewriteScript(in: copy, change)
        return copy
    }
}

/// LAB-001-B step 1: replay the complete fixture interaction from a clean state. Fixture path:
/// the replay proves the domain contract the Action Atlas actions call, not an intent, a view, or
/// a device.
@Suite struct ActionAtlasShowcaseTests {
    @Test func theShowcaseSeedIsTheAppsDemoSeedByteForByte() throws {
        #expect(try ActionAtlasShowcase.data("seed.json") == (try Data(contentsOf: ActionAtlasShowcase.appSeed)))
    }

    @Test func theShowcaseLoadsWithTheHashesOfItsExactBytes() throws {
        let script = try ActionAtlasShowcase.script()
        func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        #expect(script.subject == "LAB-001")
        #expect(script.dataTier == .publicFixture)
        #expect(script.seed.collections.count == 3 && script.seed.items.count == 12)
        #expect(script.inputs.map(\.reference) == [
            "script:action-atlas@sha256:\(hex(try ActionAtlasShowcase.data("script.json")))",
            "seed:action-atlas@sha256:\(hex(try Data(contentsOf: ActionAtlasShowcase.appSeed)))",
        ])
    }

    @Test func theInteractionPassesFromACleanStoreAndResetLeavesThePersonsDataAlone() async throws {
        let run = await DemoRunner(store: .temporarySQLite).run(try ActionAtlasShowcase.script())
        checkStepInvariants(run)
        #expect(run.result == .passed, "\(run.outcome.summary)")
        #expect(run.steps.count == 19)

        let state = try #require(run.finalState)
        #expect(state.collections.count == 4 && state.items.count == 13)
        let notes = try #require(state.collections.first { $0.id == ActionAtlasShowcase.fieldNotes })
        #expect(notes.namespace == .user && notes.revision == .initial && !notes.isArchived)
        let graphite = try #require(state.items.first { $0.id == ActionAtlasShowcase.graphite })
        #expect(graphite.namespace == .user)
        #expect(graphite.note.value == "Soft, 6B. Smudges easily.")
        #expect(graphite.revision.rawValue == 4, "created, updated, archived, restored")
        #expect(!graphite.isArchived)
        let amber = try #require(state.items.first { $0.id == ActionAtlasShowcase.amber })
        #expect(amber.namespace == .demo)
        #expect(amber.title.value == "Amber swatch", "the second Reset Demo restored the seed title")
        #expect(amber.revision.rawValue == 3, "restored at its next revision, never back to 1")

        // The second Reset Demo touched only demo entities.
        let reset = try #require(run.steps.first { $0.id == name("reset-again") }?.receipt)
        #expect(reset.changes.map(\.entity) == [.item(ActionAtlasShowcase.amber)])
        #expect(reset.removed.isEmpty)
        #expect(reset.undo == nil)

        // The archive's receipt offered the undo the script then used.
        let archive = try #require(run.steps.first { $0.id == name("archive-item") }?.receipt)
        #expect(archive.undo == .restoreItem(id: ActionAtlasShowcase.graphite, expected: revision(3)))
        let approval = try #require(run.steps.first { $0.id == name("approve-archive") }?.approval)
        #expect(approval.operation == .archiveItem && approval.target == "item \(ActionAtlasShowcase.graphite)")
    }

    @Test func replaysShareOneFingerprintAcrossRunsAndStores() async throws {
        let script = try ActionAtlasShowcase.script()
        let first = await DemoRunner(store: .temporarySQLite).run(script)
        let second = await DemoRunner(store: .temporarySQLite, clock: SuspendingIntervalClock()).run(script)
        let inMemory = await DemoRunner.manual().run(script)
        #expect(first.result == .passed && second.result == .passed && inMemory.result == .passed)
        #expect(ReplayComparison(first, second) == .identical(fingerprint: first.replayFingerprint))
        #expect(ReplayComparison(first, inMemory).isIdentical)
        #expect(first.id != second.id)
    }

    /// The same interaction submitted as the App Intent adapter: same state and receipts, and each
    /// receipt names the adapter it arrived through. No intent type runs here; the Mac hosted tests
    /// run the intents themselves.
    @Test func theAppIntentAdapterReachesTheSameStateWithReceiptsNamingIt() async throws {
        let script = try ActionAtlasShowcase.script()
        let ui = await DemoRunner(store: .temporarySQLite).run(script)
        let intent = await DemoRunner(adapter: .appIntent, store: .temporarySQLite).run(script)
        checkStepInvariants(intent)
        #expect(ui.result == .passed && intent.result == .passed)
        #expect(intent.finalState == ui.finalState)
        #expect(ReplayComparison(ui, intent) != .identical(fingerprint: ui.replayFingerprint), "the adapter is part of the result")

        let pairs = zip(ui.steps, intent.steps).compactMap { pair in pair.0.receipt.map { ($0, pair.1.receipt) } }
        #expect(pairs.count == 8)
        for (fromUI, fromIntent) in pairs {
            let fromIntent = try #require(fromIntent)
            #expect(fromUI.admitted.adapter == .appUI && fromIntent.admitted.adapter == .appIntent)
            #expect(fromIntent.operationID == fromUI.operationID)
            #expect(fromIntent.requestID == fromUI.requestID)
            #expect(fromIntent.admitted.operation == fromUI.admitted.operation)
            #expect(fromIntent.status == fromUI.status)
            #expect(fromIntent.changes == fromUI.changes)
            #expect(fromIntent.removed == fromUI.removed)
            #expect(fromIntent.summary == fromUI.summary)
            #expect(fromIntent.undo == fromUI.undo)
        }
        #expect(intent.steps.compactMap(\.approval).allSatisfy { $0.adapter == .appIntent })
    }

    /// Denial: without the person's approval the archive is refused at the commit, nothing after
    /// it runs, and the item is not archived.
    @Test func withoutTheApprovalTheArchiveIsRefused() async throws {
        let temporary = try TemporaryFolder()
        let folder = try ActionAtlasShowcase.variant(in: temporary) { object in
            let steps = object["steps"] as? [[String: Any]] ?? []
            object["steps"] = steps.filter { $0["id"] as? String != "approve-archive" }
        }
        let run = await DemoRunner.manual().run(try DemoScript(folder: folder))
        checkStepInvariants(run)
        #expect(run.result == .failed)
        let archive = try #require(run.steps.first { $0.id == name("archive-item") })
        #expect(archive.result == .failed)
        #expect(archive.outcome.detail.contains("no live approval covers this commit-destructive through app-ui"))
        #expect(archive.receipt == nil)
        #expect(run.steps.drop { $0.id != name("archive-item") }.dropFirst().allSatisfy { $0.disposition == .skipped })
        let graphite = try #require(run.finalState?.items.first { $0.id == ActionAtlasShowcase.graphite })
        #expect(!graphite.isArchived && graphite.revision.rawValue == 2)
    }

    /// Cancellation: changes that committed before the cancel stay; the rest never start.
    @Test func aCancelledReplayCommitsNothingAfterTheCancel() async throws {
        let run = await Task {
            await DemoRunner.manual().run(try! ActionAtlasShowcase.script()) { record in
                if record.id == name("create-item") { cancelCurrentTask() }
            }
        }.value
        checkStepInvariants(run)
        #expect(run.result == .notRun)
        let index = try #require(run.steps.firstIndex { $0.id == name("create-item") })
        #expect(run.steps[...index].allSatisfy { $0.result == .passed })
        #expect(run.steps[(index + 1)...].allSatisfy { $0.disposition == .cancelled && $0.result == .notRun })
        let state = try #require(run.finalState)
        #expect(state.items.first { $0.id == ActionAtlasShowcase.graphite }?.revision == .initial)
        #expect(state.items.first { $0.id == ActionAtlasShowcase.amber }?.title.value == "Amber swatch")
    }
}

/// The LAB-001 evidence export: the showcase replayed twice as the app UI and twice as the App
/// Intent adapter, on SQLite with the continuous clock, then exported through the rights and
/// privacy review.
///
/// It writes into a temporary folder that is removed afterwards. To keep the export, name a folder
/// and the build facts; with a folder named, every build fact is required:
///
///     LAB_DEMO_EVIDENCE_DIR=<folder> LAB_SOURCE_REVISION=<sha> LAB_SDK_NAME=macosx27.0 \
///     LAB_XCODE_VERSION=27.0 LAB_XCODE_BUILD=27A266a \
///     swift test --package-path Packages/LabDemo --filter ActionAtlasShowcaseEvidence
///
/// `LAB_HOST_EVIDENCE_RECORD=<file>` adds the record the Mac hosted test
/// `ActionAtlasHostEvidenceTests` attached, exported from its result bundle, so it passes the same
/// review. It must decode as an `EvidenceRecord` for LAB-001 from the same source revision.
///
/// Keep the export outside `evidence/`, and copy its `records/*.json` into `evidence/LAB-001/`.
@Suite struct ActionAtlasShowcaseEvidence {
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
        var hostArtifacts: [ExportArtifact] = []
        if let path = environment["LAB_HOST_EVIDENCE_RECORD"] {
            let host = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: URL(filePath: path)))
            try #require(host.subject == "LAB-001")
            try #require(host.provenance.sourceRevision == provenance.sourceRevision, "one source revision per export")
            hostArtifacts.append(try .record(host, at: "records/action-atlas-host-ui-and-intent.json", tier: .publicFixture))
        }

        let script = try ActionAtlasShowcase.script()
        let uiRunner = DemoRunner(adapter: .appUI, store: .temporarySQLite)
        let intentRunner = DemoRunner(adapter: .appIntent, store: .temporarySQLite)
        let ui = [await uiRunner.run(script), await uiRunner.run(script)]
        let intent = [await intentRunner.run(script), await intentRunner.run(script)]
        for run in ui + intent { checkStepInvariants(run) }

        // Nothing is recorded unless the replays passed and agree.
        try #require((ui + intent).allSatisfy { $0.result == .passed })
        try #require(ReplayComparison(ui[0], ui[1]).isIdentical)
        try #require(ReplayComparison(intent[0], intent[1]).isIdentical)
        try #require(intent[0].finalState == ui[0].finalState)

        let uiRecord = try ui[0].evidenceRecord(
            provenance: provenance,
            check: "Action Atlas showcase replayed twice from a clean SQLite store as the app-UI adapter; both replays share one fingerprint"
        )
        let intentRecord = try intent[0].evidenceRecord(
            provenance: provenance,
            check: "Action Atlas showcase replayed twice from a clean SQLite store as the App Intent adapter (no intent type ran); both replays share one fingerprint and end in the app-UI replay's state"
        )
        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "LAB-001 Action Atlas showcase replay",
            artifacts: [
                try .run(ui[0], at: "runs/app-ui-first.json"),
                try .run(ui[1], at: "runs/app-ui-second.json"),
                try .run(intent[0], at: "runs/app-intent-first.json"),
                try .run(intent[1], at: "runs/app-intent-second.json"),
                try .record(uiRecord, at: "records/action-atlas-showcase-app-ui.json", tier: .publicFixture),
                try .record(intentRecord, at: "records/action-atlas-showcase-app-intent.json", tier: .publicFixture),
                try .file("action-atlas/script.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/script.json"),
                try .file("action-atlas/seed.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/seed.json"),
            ] + hostArtifacts,
            untested: [
                "The App Intents run by Shortcuts or Siri, on any device.",
                "A physical iPhone or iPad: no device was used.",
            ],
            provenance: provenance
        ))
        #expect(preview.result == .passed)
        #expect(preview.refused.isEmpty)
        #expect(preview.reviews.count == 8 + hostArtifacts.count)
        #expect(preview.reviews.allSatisfy { $0.tier == .publicFixture && $0.decision == .approved })
        #expect(preview.summaryText.hasPrefix("Passed: 4 demo runs and \(2 + hostArtifacts.count) evidence records exported; every one passed."))

        let temporary = try TemporaryFolder()
        let written = try preview.write(into: keep ?? temporary.url, folderName: "lab-001-action-atlas-showcase")
        #expect(temporary.files(below: written) == Set(preview.files.map(\.path)))
        for (path, record) in [
            ("records/action-atlas-showcase-app-ui.json", uiRecord),
            ("records/action-atlas-showcase-app-intent.json", intentRecord),
        ] {
            let stored = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: written.appending(path: path)))
            #expect(stored == record)
            #expect(stored.subject == "LAB-001")
            #expect(stored.path == .fixture)
            #expect(stored.supportedState == .implemented, "a replay never supports device-verified")
            #expect(stored.inputs == script.inputs.map(\.reference))
            #expect(stored.limitations.first == DemoRun.fixtureLimitation)
        }
        #expect(uiRecord.outcome.detail.contains("Adapter app-ui"))
        #expect(intentRecord.outcome.detail.contains("Adapter app-intent"))
    }
}
