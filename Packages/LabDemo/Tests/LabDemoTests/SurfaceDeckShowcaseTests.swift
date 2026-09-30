import CryptoKit
import Foundation
@testable import LabDemo
import LabDomain
import LabStore
import LabSupport
import Testing

/// `Fixtures/showcase/surface-deck/`: LAB-004's fixture interaction, replayed from a clean store.
enum SurfaceDeckShowcase {
    static let folder = Showcase.fixtures.appending(path: "surface-deck", directoryHint: .isDirectory)
    /// The seed the app bundles and seeds its first run with.
    static let appSeed = Showcase.repositoryRoot.appending(path: "Fixtures/demo/seed.json")
    /// Where the app, its widget, and its Controls name the one demo session.
    static let moduleSource = Showcase.repositoryRoot.appending(path: "Packages/LabFeatures/Sources/SurfaceDeck/SurfaceDeck.swift")

    static let session = SessionID(rawValue: UUID(uuidString: "9B54BD13-C217-4447-BF24-6664727C367A")!)
    static let swatches = CollectionID(rawValue: UUID(uuidString: "A40194B3-5E91-4C5C-AE02-CF703BE23224")!)

    static func script() throws -> DemoScript {
        try DemoScript(folder: folder)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: name))
    }

    /// A copy of the showcase folder with its script changed, for tests that need a variant.
    static func variant(in temporary: TemporaryFolder, _ change: (inout [String: Any]) -> Void) throws -> URL {
        let copy = temporary.url.appending(path: "surface-deck", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: folder, to: copy)
        try rewriteScript(in: copy, change)
        return copy
    }

    static func receipt(_ run: DemoRun, _ step: String) -> ActionReceipt? {
        run.steps.first { $0.id == name(step) }?.receipt
    }
}

/// LAB-004-B step 1: replay the complete fixture interaction from a clean state. Fixture path: the
/// replay proves the domain contract the deck, the widget's toggle, and the Controls call, not an
/// intent, WidgetKit, the snapshot, a view, or a device.
@Suite struct SurfaceDeckShowcaseTests {
    @Test func theShowcaseSeedIsTheAppsDemoSeedByteForByte() throws {
        #expect(try SurfaceDeckShowcase.data("seed.json") == (try Data(contentsOf: SurfaceDeckShowcase.appSeed)))
    }

    @Test func theShowcaseLoadsWithTheHashesOfItsExactBytesAndTheAppsSession() throws {
        let script = try SurfaceDeckShowcase.script()
        func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        #expect(script.subject == "LAB-004")
        #expect(script.dataTier == .publicFixture)
        #expect(script.steps.count == 9)
        #expect(script.inputs.map(\.reference) == [
            "script:surface-deck@sha256:\(hex(try SurfaceDeckShowcase.data("script.json")))",
            "seed:surface-deck@sha256:\(hex(try Data(contentsOf: SurfaceDeckShowcase.appSeed)))",
        ])
        let start = try #require(script.steps.first { $0.id == name("start-session") })
        #expect(start.action == .perform(
            request: RequestID(rawValue: UUID(uuidString: "42C528A8-FFF5-4EDA-91AB-299E9C3BE78F")!),
            operation: .domain(.setSession(id: SurfaceDeckShowcase.session, expected: nil, running: true))
        ))
        // The session is the one every surface in the app names.
        let source = try String(contentsOf: SurfaceDeckShowcase.moduleSource, encoding: .utf8)
        #expect(source.contains("UUID(uuidString: \"\(SurfaceDeckShowcase.session.rawValue.uuidString)\")"))
    }

    @Test func theInteractionPassesFromACleanStoreAndResetOnlyPausesTheSession() async throws {
        let run = await DemoRunner(store: .temporarySQLite).run(try SurfaceDeckShowcase.script())
        checkStepInvariants(run)
        #expect(run.result == .passed, "\(run.outcome.summary)")
        #expect(run.steps.count == 9)

        let state = try #require(run.finalState)
        #expect(state.sessions == [LabSession(id: SurfaceDeckShowcase.session, isRunning: true, revision: revision(5))])
        #expect(state.collections.count == 3 && state.items.count == 12)
        #expect(state.items.allSatisfy { $0.revision == .initial && !$0.isArchived }, "no session change touched a sample")

        let session = EntityReference.session(SurfaceDeckShowcase.session)
        let start = try #require(SurfaceDeckShowcase.receipt(run, "start-session"))
        #expect(start.changes.map(\.entity) == [session])
        #expect(start.changes.map(\.previousRevision) == [nil] && start.changes.map(\.newRevision) == [.initial])
        #expect(start.summary == "Started the demo session.")
        #expect(start.undo == .setSession(id: SurfaceDeckShowcase.session, expected: .initial, running: false))

        let pause = try #require(SurfaceDeckShowcase.receipt(run, "pause-session"))
        #expect(pause.summary == "Paused the demo session.")
        #expect(pause.undo == .setSession(id: SurfaceDeckShowcase.session, expected: revision(2), running: true))
        let undo = try #require(SurfaceDeckShowcase.receipt(run, "undo-pause"))
        #expect(undo.admitted.operation == pause.undo)
        #expect(undo.changes.map(\.newRevision) == [revision(3)])

        // The second Reset Demo paused the session, removed nothing, and offers no undo.
        let reset = try #require(SurfaceDeckShowcase.receipt(run, "reset-again"))
        #expect(reset.changes.map(\.entity) == [session])
        #expect(reset.changes.map(\.previousRevision) == [revision(3)] && reset.changes.map(\.newRevision) == [revision(4)])
        #expect(reset.removed.isEmpty && reset.undo == nil)
        #expect(reset.summary == "Reset the demo to its original 3 collections and 12 items: paused 1 session.")

        let again = try #require(SurfaceDeckShowcase.receipt(run, "start-after-reset"))
        #expect(again.changes.map(\.newRevision) == [revision(5)])

        // Starting and pausing needed no approval: only the two resets asked for one.
        #expect(run.steps.compactMap(\.approval).map(\.operation) == [.resetDemo, .resetDemo])
        let sessionReceipts = run.steps.compactMap(\.receipt).filter { $0.admitted.operation.kind == .setSession }
        #expect(sessionReceipts.count == 4)
        #expect(sessionReceipts.allSatisfy { $0.status == .committed && $0.admitted.adapter == .appUI })
    }

    @Test func replaysShareOneFingerprintAcrossRunsAndStores() async throws {
        let script = try SurfaceDeckShowcase.script()
        let first = await DemoRunner(store: .temporarySQLite).run(script)
        let second = await DemoRunner(store: .temporarySQLite, clock: SuspendingIntervalClock()).run(script)
        let inMemory = await DemoRunner.manual().run(script)
        #expect(first.result == .passed && second.result == .passed && inMemory.result == .passed)
        #expect(ReplayComparison(first, second) == .identical(fingerprint: first.replayFingerprint))
        #expect(ReplayComparison(first, inMemory).isIdentical)
        #expect(first.id != second.id)
    }

    /// The same interaction submitted as the App Intent adapter, the one the widget's toggle, the
    /// Control, and Shortcuts use: same state and receipts, each naming its adapter. No intent type
    /// runs here; the SurfaceDeck package and Mac hosted tests run the intents themselves.
    @Test func theAppIntentAdapterReachesTheSameStateWithReceiptsNamingIt() async throws {
        let script = try SurfaceDeckShowcase.script()
        let ui = await DemoRunner(store: .temporarySQLite).run(script)
        let intent = await DemoRunner(adapter: .appIntent, store: .temporarySQLite).run(script)
        checkStepInvariants(intent)
        #expect(ui.result == .passed && intent.result == .passed)
        #expect(intent.finalState == ui.finalState)
        #expect(ReplayComparison(ui, intent) != .identical(fingerprint: ui.replayFingerprint), "the adapter is part of the result")

        let pairs = zip(ui.steps, intent.steps).compactMap { pair in pair.0.receipt.map { ($0, pair.1.receipt) } }
        #expect(pairs.count == 6)
        for (fromUI, fromIntent) in pairs {
            let fromIntent = try #require(fromIntent)
            #expect(fromUI.admitted.adapter == .appUI && fromIntent.admitted.adapter == .appIntent)
            #expect(fromIntent.operationID == fromUI.operationID)
            #expect(fromIntent.admitted.operation == fromUI.admitted.operation)
            #expect(fromIntent.changes == fromUI.changes)
            #expect(fromIntent.summary == fromUI.summary)
            #expect(fromIntent.undo == fromUI.undo)
        }
    }

    /// Stale state: a toggle from a surface that still shows revision 1 is answered with a conflict
    /// receipt and changes nothing. The runner counts a conflict as a step that did not pass, so
    /// the showcase itself leaves this case out and the qualification tests carry it.
    @Test func aStaleToggleIsAConflictThatChangesNothing() async throws {
        let temporary = try TemporaryFolder()
        let folder = try SurfaceDeckShowcase.variant(in: temporary) { object in
            var steps = object["steps"] as? [[String: Any]] ?? []
            let index = steps.firstIndex { $0["id"] as? String == "undo-pause" }! + 1
            steps.insert([
                "id": "stale-pause",
                "request": "3F1C0B6E-6C1B-4B55-9D51-0C1D6A3E9E21",
                "setSession": ["id": SurfaceDeckShowcase.session.rawValue.uuidString, "expected": 1, "running": false],
            ], at: index)
            object["steps"] = steps
        }
        let run = await DemoRunner.manual().run(try DemoScript(folder: folder))
        checkStepInvariants(run)
        #expect(run.result == .failed)
        let stale = try #require(run.steps.first { $0.id == name("stale-pause") })
        #expect(stale.result == .failed)
        #expect(stale.outcome.detail == "Conflict, nothing changed: Not applied because the demo session changed: expected revision 1, found 3.")
        let receipt = try #require(stale.receipt)
        #expect(receipt.conflict?.current == revision(3) && receipt.changes.isEmpty && receipt.undo == nil)
        #expect(run.steps.drop { $0.id != name("stale-pause") }.dropFirst().allSatisfy { $0.disposition == .skipped })
        #expect(run.finalState?.sessions == [LabSession(id: SurfaceDeckShowcase.session, isRunning: true, revision: revision(3))])
    }

    /// Cancellation: the change that committed before the cancel stays; the rest never start.
    @Test func aCancelledReplayCommitsNothingAfterTheCancel() async throws {
        let run = await Task {
            await DemoRunner.manual().run(try! SurfaceDeckShowcase.script()) { record in
                if record.id == name("start-session") { cancelCurrentTask() }
            }
        }.value
        checkStepInvariants(run)
        #expect(run.result == .notRun)
        let index = try #require(run.steps.firstIndex { $0.id == name("start-session") })
        #expect(run.steps[...index].allSatisfy { $0.result == .passed })
        #expect(run.steps[(index + 1)...].allSatisfy { $0.disposition == .cancelled && $0.result == .notRun })
        #expect(run.finalState?.sessions == [LabSession(id: SurfaceDeckShowcase.session, isRunning: true)])
    }

    /// A `setSession` step is validated like every other operation: its fields are fixed, and it
    /// states whether the session should run.
    @Test func sessionStepsAreValidatedLikeEveryOtherOperation() throws {
        func load(_ change: @escaping ([String: Any]) -> [String: Any]) throws -> DemoScriptError? {
            let temporary = try TemporaryFolder()
            let folder = try SurfaceDeckShowcase.variant(in: temporary) { object in
                var steps = object["steps"] as? [[String: Any]] ?? []
                steps[2]["setSession"] = change(steps[2]["setSession"] as? [String: Any] ?? [:])
                object["steps"] = steps
            }
            do {
                _ = try DemoScript(folder: folder)
                return nil
            } catch {
                return error
            }
        }
        #expect(try load { $0 } == nil)
        #expect(try load { var entry = $0; entry["running"] = nil; return entry } == .malformed(path: "steps[2].setSession.running"))
        #expect(try load { var entry = $0; entry["id"] = nil; return entry } == .malformed(path: "steps[2].setSession.id"))
        #expect(try load { var entry = $0; entry["namespace"] = "user"; return entry } == .unknownField(path: "steps[2].setSession.namespace"))
        #expect(try load { var entry = $0; entry["expected"] = 0; return entry } == .invalidValue(path: "steps[2].setSession.expected"))
        #expect(try load { var entry = $0; entry["running"] = "yes"; return entry } == .malformed(path: "steps[2].setSession.running"))
    }

    /// A run that never starts a session encodes its final state exactly as before sessions were
    /// recorded, so the LAB-001 replay fingerprints stay reproducible.
    @Test func aStateWithoutSessionsEncodesAsBefore() throws {
        let empty = try jsonObject(try Canonical.text(DemoState(collections: [], items: [])))
        #expect(Set(empty.keys) == ["collections", "items"])
        let withSession = try jsonObject(try Canonical.text(DemoState(
            collections: [], items: [], sessions: [LabSession(id: SurfaceDeckShowcase.session, isRunning: true)]
        )))
        #expect(Set(withSession.keys) == ["collections", "items", "sessions"])
    }
}

/// The LAB-004 evidence export: the showcase replayed twice as the app UI and twice as the App
/// Intent adapter, on SQLite with the continuous clock, then exported through the rights and
/// privacy review.
///
/// It writes into a temporary folder that is removed afterwards. To keep the export, name a folder
/// and the build facts; with a folder named, every build fact is required:
///
///     LAB_DEMO_EVIDENCE_DIR=<folder> LAB_SOURCE_REVISION=<sha> LAB_SDK_NAME=macosx27.0 \
///     LAB_XCODE_VERSION=27.0 LAB_XCODE_BUILD=27A266a \
///     swift test --package-path Packages/LabDemo --filter SurfaceDeckShowcaseEvidence
///
/// `LAB_HOST_EVIDENCE_RECORD=<file>` adds the record the Mac hosted test
/// `SurfaceDeckHostEvidenceTests` attached, exported from its result bundle, so it passes the same
/// review. It must decode as an `EvidenceRecord` for LAB-004 from the same source revision.
///
/// Keep the export outside `evidence/`, and copy its `records/*.json` into `evidence/LAB-004/`.
@Suite struct SurfaceDeckShowcaseEvidence {
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
            try #require(host.subject == "LAB-004")
            try #require(host.provenance.sourceRevision == provenance.sourceRevision, "one source revision per export")
            hostArtifacts.append(try .record(host, at: "records/surface-deck-host-qualification.json", tier: .publicFixture))
        }

        let script = try SurfaceDeckShowcase.script()
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
            check: "Surface Deck showcase replayed twice from a clean SQLite store as the app-UI adapter; both replays share one fingerprint"
        )
        let intentRecord = try intent[0].evidenceRecord(
            provenance: provenance,
            check: "Surface Deck showcase replayed twice from a clean SQLite store as the App Intent adapter (no intent type ran); both replays share one fingerprint and end in the app-UI replay's state"
        )
        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "LAB-004 Surface Deck showcase replay",
            artifacts: [
                try .run(ui[0], at: "runs/app-ui-first.json"),
                try .run(ui[1], at: "runs/app-ui-second.json"),
                try .run(intent[0], at: "runs/app-intent-first.json"),
                try .run(intent[1], at: "runs/app-intent-second.json"),
                try .record(uiRecord, at: "records/surface-deck-showcase-app-ui.json", tier: .publicFixture),
                try .record(intentRecord, at: "records/surface-deck-showcase-app-intent.json", tier: .publicFixture),
                try .file("surface-deck/script.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/script.json"),
                try .file("surface-deck/seed.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/seed.json"),
            ] + hostArtifacts,
            untested: [
                "The widget and the Controls drawn by the system, and their App Intents run by the system, on any device.",
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
        let written = try preview.write(into: keep ?? temporary.url, folderName: "lab-004-surface-deck-showcase")
        #expect(temporary.files(below: written) == Set(preview.files.map(\.path)))
        for (path, record) in [
            ("records/surface-deck-showcase-app-ui.json", uiRecord),
            ("records/surface-deck-showcase-app-intent.json", intentRecord),
        ] {
            let stored = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: written.appending(path: path)))
            #expect(stored == record)
            #expect(stored.subject == "LAB-004")
            #expect(stored.path == .fixture)
            #expect(stored.supportedState == .implemented, "a replay never supports device-verified")
            #expect(stored.inputs == script.inputs.map(\.reference))
            #expect(stored.limitations.first == DemoRun.fixtureLimitation)
        }
        #expect(uiRecord.outcome.detail.contains("Adapter app-ui"))
        #expect(intentRecord.outcome.detail.contains("Adapter app-intent"))
    }
}
