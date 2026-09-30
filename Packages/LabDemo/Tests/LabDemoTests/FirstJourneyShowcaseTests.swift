import CryptoKit
import Foundation
@testable import LabDemo
import LabDomain
import LabStore
import LabSupport
import Testing

/// `Fixtures/showcase/first-journey/`: CORE-012's first six-lab journey, replayed from a clean
/// store. The intake, the review, the App Intents, and the export happen in `FirstJourneyTests`
/// (`Packages/LabFeatures`), which commits exactly this script's operations; this replay commits
/// them on the lab's SQLite store and records the evidence.
enum FirstJourneyShowcase {
    static let folder = Showcase.fixtures.appending(path: "first-journey", directoryHint: .isDirectory)
    static let appSeed = Showcase.repositoryRoot.appending(path: "Fixtures/demo/seed.json")
    static let sharedNote = Showcase.repositoryRoot.appending(path: "Fixtures/intelligence/intelligence-injected-note.txt")

    static func script() throws -> DemoScript {
        try DemoScript(folder: folder)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: name))
    }

    static let fieldNotes = CollectionID(rawValue: UUID(uuidString: "06D9663A-9835-44CE-B9E9-C048717D597A")!)
    /// The shared object: the note, added to Field notes. `ImportAdopter` derives its ID.
    static let object = ItemID(rawValue: UUID(uuidString: "C784FB5A-4D9A-8895-9AE7-9418D700541D")!)
    static let kraft = ItemID(rawValue: UUID(uuidString: "6E2CED9D-B946-4188-8417-2E85C6A7268C")!)
    static let session = SessionID(rawValue: UUID(uuidString: "9B54BD13-C217-4447-BF24-6664727C367A")!)
    static let renamedTitle = "Kraft card wear note"
    static let kraftSeedNote = "Brown and stiff. Takes pencil well."

    static func receipt(_ run: DemoRun, _ step: String) -> ActionReceipt? {
        run.steps.first { $0.id == name(step) }?.receipt
    }

    static func variant(in temporary: TemporaryFolder, _ change: (inout [String: Any]) -> Void) throws -> URL {
        let copy = temporary.url.appending(path: "first-journey", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: folder, to: copy)
        try rewriteScript(in: copy, change)
        return copy
    }
}

/// CORE-012 step 1: the journey's commits from a clean state. Fixture path: it proves the
/// operations and the SQLite store, not the intake, a view, an intent, or a device.
@Suite struct FirstJourneyShowcaseTests {
    @Test func theShowcaseSeedIsTheAppsDemoSeedByteForByte() throws {
        #expect(try FirstJourneyShowcase.data("seed.json") == (try Data(contentsOf: FirstJourneyShowcase.appSeed)))
    }

    @Test func theShowcaseLoadsWithTheHashesOfItsExactBytes() throws {
        let script = try FirstJourneyShowcase.script()
        func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        #expect(script.subject == "CORE-012")
        #expect(script.dataTier == .publicFixture)
        #expect(script.steps.count == 35)
        #expect(script.inputs.map(\.reference) == [
            "script:first-journey@sha256:\(hex(try FirstJourneyShowcase.data("script.json")))",
            "seed:first-journey@sha256:\(hex(try Data(contentsOf: FirstJourneyShowcase.appSeed)))",
        ])
        // The object's note is the fixture's text, byte for byte.
        let add = try #require(script.steps.first { $0.id == name("add-object") })
        guard case .perform(_, .domain(.createItem(let draft))) = add.action else {
            Issue.record("add-object is not a createItem: \(add.action)")
            return
        }
        #expect(draft.id == FirstJourneyShowcase.object && draft.collectionID == FirstJourneyShowcase.fieldNotes)
        #expect(Data(draft.note.value.utf8) == (try Data(contentsOf: FirstJourneyShowcase.sharedNote)))
    }

    @Test func theJourneyPassesFromACleanStoreAndResetLeavesTheObjectAlone() async throws {
        let run = await DemoRunner(store: .temporarySQLite).run(try FirstJourneyShowcase.script())
        checkStepInvariants(run)
        #expect(run.result == .passed, "\(run.outcome.summary)")
        #expect(run.steps.count == 35)

        let state = try #require(run.finalState)
        #expect(state.collections.count == 4 && state.items.count == 13)
        let fieldNotes = try #require(state.collections.first { $0.id == FirstJourneyShowcase.fieldNotes })
        #expect(fieldNotes.namespace == .user && fieldNotes.title.value == "Field notes")
        let object = try #require(state.items.first { $0.id == FirstJourneyShowcase.object })
        #expect(object.namespace == .user && object.collectionID == FirstJourneyShowcase.fieldNotes)
        #expect(object.title.value == FirstJourneyShowcase.renamedTitle && object.revision == revision(4) && !object.isArchived)
        #expect(Data(object.note.value.utf8) == (try Data(contentsOf: FirstJourneyShowcase.sharedNote)))
        // Every demo sample is as seeded or restored to it, and the session is paused.
        let demo = state.items.filter { $0.namespace == .demo }
        #expect(demo.count == 12 && demo.allSatisfy { !$0.isArchived })
        #expect(demo.first { $0.id == FirstJourneyShowcase.kraft }?.note.value == FirstJourneyShowcase.kraftSeedNote)
        #expect(state.sessions == [LabSession(id: FirstJourneyShowcase.session, isRunning: false, revision: revision(4))])

        // Every change committed as the app UI; the object's four changes and nothing else moved it.
        let receipts = run.steps.compactMap(\.receipt)
        #expect(receipts.count == 18)
        #expect(receipts.allSatisfy { $0.status == .committed && $0.admitted.adapter == .appUI })
        let objectChanges = receipts.filter { $0.affectedEntities.contains(.item(FirstJourneyShowcase.object)) }
        #expect(objectChanges.map { $0.admitted.operation.kind } == [.createItem, .updateItem, .archiveItem, .restoreItem])

        // Only the reset, the Add, the archive, and the practice archives asked for an approval.
        #expect(run.steps.compactMap(\.approval).map(\.operation) == [.resetDemo, .createItem, .archiveItem]
            + Array(repeating: .archiveItem, count: 6) + [.resetDemo])

        // The second Reset Demo put back the kraft card, the five practice samples still archived,
        // and the session; it removed nothing and did not touch the object or its collection.
        let reset = try #require(FirstJourneyShowcase.receipt(run, "reset-again"))
        #expect(reset.changes.count == 7 && reset.removed.isEmpty && reset.undo == nil)
        #expect(reset.changes.contains { $0.entity == .item(FirstJourneyShowcase.kraft) })
        #expect(reset.changes.contains { $0.entity == .session(FirstJourneyShowcase.session) })
        #expect(!reset.affectedEntities.contains(.item(FirstJourneyShowcase.object)))
        #expect(!reset.affectedEntities.contains(.collection(FirstJourneyShowcase.fieldNotes)))
    }

    @Test func replaysShareOneFingerprintAcrossRunsAndStores() async throws {
        let script = try FirstJourneyShowcase.script()
        let first = await DemoRunner(store: .temporarySQLite).run(script)
        let second = await DemoRunner(store: .temporarySQLite, clock: SuspendingIntervalClock()).run(script)
        let inMemory = await DemoRunner.manual().run(script)
        #expect(first.result == .passed && second.result == .passed && inMemory.result == .passed)
        #expect(ReplayComparison(first, second) == .identical(fingerprint: first.replayFingerprint))
        #expect(ReplayComparison(first, inMemory).isIdentical)
        #expect(first.id != second.id)
    }

    /// Denial: composed as the model-tool adapter, the replay can change nothing, not even the
    /// first Reset Demo.
    @Test func aModelToolCanChangeNothing() async throws {
        let run = await DemoRunner.manual(adapter: .modelTool).run(try FirstJourneyShowcase.script())
        checkStepInvariants(run)
        #expect(run.result == .failed)
        #expect(run.steps.first { $0.result == .failed }?.id == name("approve-reset"))
        #expect(run.finalState?.items.isEmpty == true && run.finalState?.collections.isEmpty == true)
    }

    /// Stale state: archiving the object from the revision it had before the rename is a
    /// conflict. Nothing after it runs, and the object keeps its new title, unarchived.
    @Test func aStaleArchiveIsAConflictThatChangesNothing() async throws {
        let temporary = try TemporaryFolder()
        let folder = try FirstJourneyShowcase.variant(in: temporary) { object in
            var steps = object["steps"] as? [[String: Any]] ?? []
            for index in steps.indices where steps[index]["id"] as? String == "archive-object" {
                steps[index]["archiveItem"] = ["id": FirstJourneyShowcase.object.rawValue.uuidString, "expected": 1]
            }
            object["steps"] = steps
        }
        let run = await DemoRunner.manual().run(try DemoScript(folder: folder))
        checkStepInvariants(run)
        #expect(run.result == .failed)
        let archive = try #require(run.steps.first { $0.id == name("archive-object") })
        #expect(archive.result == .failed)
        #expect(archive.receipt?.conflict != nil && archive.receipt?.changes.isEmpty == true)
        #expect(run.steps.drop { $0.id != name("archive-object") }.dropFirst().allSatisfy { $0.disposition == .skipped })
        let object = try #require(run.finalState?.items.first { $0.id == FirstJourneyShowcase.object })
        #expect(object.title.value == FirstJourneyShowcase.renamedTitle && object.revision == revision(2) && !object.isArchived)
    }

    /// Cancellation: the object added before the cancel stays; nothing after it is committed.
    @Test func aCancelledReplayKeepsTheObjectAndCommitsNothingAfter() async throws {
        let run = await Task {
            await DemoRunner.manual().run(try! FirstJourneyShowcase.script()) { record in
                if record.id == name("add-object") { cancelCurrentTask() }
            }
        }.value
        checkStepInvariants(run)
        #expect(run.result == .notRun)
        let index = try #require(run.steps.firstIndex { $0.id == name("add-object") })
        #expect(run.steps[...index].allSatisfy { $0.result == .passed })
        #expect(run.steps[(index + 1)...].allSatisfy { $0.disposition == .cancelled && $0.result == .notRun })
        let state = try #require(run.finalState)
        let object = try #require(state.items.first { $0.id == FirstJourneyShowcase.object })
        #expect(object.revision == .initial)
        #expect(state.items.first { $0.id == FirstJourneyShowcase.kraft }?.note.value == FirstJourneyShowcase.kraftSeedNote)
        #expect(state.sessions.isEmpty)
    }
}

/// The CORE-012 evidence export: the showcase replayed twice as the app UI on SQLite, then
/// exported through the rights and privacy review with its script, seed, and the shared note.
///
/// It writes into a temporary folder that is removed afterwards. To keep the export, name a folder
/// and the build facts; with a folder named, every build fact is required:
///
///     LAB_DEMO_EVIDENCE_DIR=<folder> LAB_SOURCE_REVISION=<sha> LAB_SDK_NAME=macosx27.0 \
///     LAB_XCODE_VERSION=27.0 LAB_XCODE_BUILD=27A266a \
///     swift test --package-path Packages/LabDemo --filter FirstJourneyShowcaseEvidence
///
/// Keep the export outside `evidence/`, and copy its `records/*.json` into `evidence/CORE-012/`.
@Suite struct FirstJourneyShowcaseEvidence {
    @Test func theShowcaseExportsEndToEnd() async throws {
        let environment = ProcessInfo.processInfo.environment
        let keep = environment["LAB_DEMO_EVIDENCE_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
        if keep != nil {
            for fact in ["LAB_SOURCE_REVISION", "LAB_SDK_NAME", "LAB_XCODE_VERSION", "LAB_XCODE_BUILD"] {
                try #require(environment[fact].map { !$0.isEmpty } == true, "a kept export names \(fact)")
            }
        }
        let provenance = BuildProvenance(
            sourceRevision: environment["LAB_SOURCE_REVISION"] ?? "unknown",
            sdkName: environment["LAB_SDK_NAME"] ?? "unknown",
            xcodeVersion: environment["LAB_XCODE_VERSION"] ?? "unknown",
            xcodeBuild: environment["LAB_XCODE_BUILD"] ?? "unknown"
        )

        let script = try FirstJourneyShowcase.script()
        let runner = DemoRunner(adapter: .appUI, store: .temporarySQLite)
        let runs = [await runner.run(script), await runner.run(script)]
        for run in runs { checkStepInvariants(run) }

        // Nothing is recorded unless both replays passed and agree.
        try #require(runs.allSatisfy { $0.result == .passed })
        try #require(ReplayComparison(runs[0], runs[1]).isIdentical)

        let record = try runs[0].evidenceRecord(
            provenance: provenance,
            check: "First six-lab journey showcase replayed twice from a clean SQLite store as the app-UI adapter: the shared object added, a reviewed proposal applied, the object renamed, archived, and restored, the session changed, the accessible task finished, and Reset Demo leaving the object alone; both replays share one fingerprint"
        )
        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "CORE-012 first six-lab journey showcase replay",
            artifacts: [
                try .run(runs[0], at: "runs/app-ui-first.json"),
                try .run(runs[1], at: "runs/app-ui-second.json"),
                try .record(record, at: "records/first-journey-showcase-app-ui.json", tier: .publicFixture),
                try .file("first-journey/script.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/script.json"),
                try .file("first-journey/seed.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/seed.json"),
                try .file(
                    "intelligence/intelligence-injected-note.txt", in: Showcase.repositoryRoot.appending(path: "Fixtures", directoryHint: .isDirectory),
                    tier: .publicFixture, at: "inputs/intelligence-injected-note.txt"
                ),
            ],
            untested: [
                "The intake, the review, the App Intents, and the export: they run in FirstJourneyTests (Packages/LabFeatures), not in this replay.",
                "The share extension, the widget, and the Control on a device: a free Personal Team cannot sign App Groups.",
                "A physical iPhone or iPad: no device was used in this replay.",
            ],
            provenance: provenance
        ))
        #expect(preview.result == .passed)
        #expect(preview.refused.isEmpty)
        #expect(preview.reviews.count == 6)
        #expect(preview.reviews.allSatisfy { $0.tier == .publicFixture && $0.decision == .approved })
        #expect(preview.summaryText.hasPrefix("Passed: 2 demo runs and 1 evidence record exported; every one passed."), "\(preview.summaryText)")

        let temporary = try TemporaryFolder()
        let written = try preview.write(into: keep ?? temporary.url, folderName: "core-012-first-journey-showcase")
        #expect(temporary.files(below: written) == Set(preview.files.map(\.path)))
        let stored = try JSONDecoder().decode(
            EvidenceRecord.self, from: Data(contentsOf: written.appending(path: "records/first-journey-showcase-app-ui.json"))
        )
        #expect(stored == record)
        #expect(stored.subject == "CORE-012")
        #expect(stored.path == .fixture)
        #expect(stored.supportedState == .implemented, "a replay never supports device-verified")
        #expect(stored.inputs == script.inputs.map(\.reference))
        #expect(stored.limitations.first == DemoRun.fixtureLimitation)
        #expect(record.outcome.detail.contains("35 of 35 steps passed"))
        #expect(record.outcome.detail.contains("Adapter app-ui"))
    }
}
