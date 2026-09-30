import CryptoKit
import Foundation
@testable import LabDemo
import LabDomain
import LabStore
import LabSupport
import Testing

/// `Fixtures/showcase/access-superpower/`: LAB-035's fixture interaction, replayed from a clean store.
enum AccessSuperpowerShowcase {
    static let folder = Showcase.fixtures.appending(path: "access-superpower", directoryHint: .isDirectory)
    /// The seed the app bundles and seeds its first run with.
    static let appSeed = Showcase.repositoryRoot.appending(path: "Fixtures/demo/seed.json")

    static func script() throws -> DemoScript {
        try DemoScript(folder: folder)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: name))
    }

    static func item(_ uuid: String) -> ItemID { ItemID(rawValue: UUID(uuidString: uuid)!) }

    static let quartz = item("AF451890-CA80-4DE9-B18B-4007066C9177")
    static let agate = item("D279FB0E-642E-463A-B3DA-299442A1C7CB")
    static let obsidian = item("C6468C0B-4BF6-48E8-AE5D-F5FC7A041097")
    static let cobalt = item("9B97BF2F-4D0B-4197-9CA8-36489DF40455")
    static let ochre = item("C8E1904C-E8DC-40A0-93D3-53F6C0FFF95D")
    static let vellum = item("6933AC83-9E61-4264-8EB8-0535B3C5E0F8")
    static let amber = item("DB666EF1-F642-43F1-B415-895B6ECFF693")
    static let graphite = item("E1C4A57E-3721-4A6A-9B15-9756CFEE8861")
    static let fieldNotes = CollectionID(rawValue: UUID(uuidString: "EAFFDC12-01A7-4206-963C-8A8A24AFE04F")!)
    static let practice = [quartz, agate, obsidian, cobalt, ochre, vellum]

    /// A copy of the showcase folder with its script changed, for tests that need a variant.
    static func variant(in temporary: TemporaryFolder, _ change: (inout [String: Any]) -> Void) throws -> URL {
        let copy = temporary.url.appending(path: "access-superpower", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: folder, to: copy)
        try rewriteScript(in: copy, change)
        return copy
    }
}

/// LAB-035-B step 1: replay the complete fixture interaction from a clean state. Fixture path:
/// the replay proves the data contract every way of finishing the task ends in (the practice
/// archives, the one restore, its undo, a miss, and Reset Practice beside the person's own data),
/// not the chart, an assistive technology, a view, or a device.
@Suite struct AccessSuperpowerShowcaseTests {
    @Test func theShowcaseSeedIsTheAppsDemoSeedByteForByte() throws {
        #expect(try AccessSuperpowerShowcase.data("seed.json") == (try Data(contentsOf: AccessSuperpowerShowcase.appSeed)))
    }

    @Test func theShowcaseLoadsWithTheHashesOfItsExactBytes() throws {
        let script = try AccessSuperpowerShowcase.script()
        func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        #expect(script.subject == "LAB-035")
        #expect(script.dataTier == .publicFixture)
        #expect(script.seed.collections.count == 3 && script.seed.items.count == 12)
        #expect(script.steps.count == 41)
        #expect(script.inputs.map(\.reference) == [
            "script:access-superpower@sha256:\(hex(try AccessSuperpowerShowcase.data("script.json")))",
            "seed:access-superpower@sha256:\(hex(try Data(contentsOf: AccessSuperpowerShowcase.appSeed)))",
        ])
    }

    @Test func theInteractionPassesFromACleanStoreAndResetPracticeLeavesThePersonsDataAlone() async throws {
        let run = await DemoRunner(store: .temporarySQLite).run(try AccessSuperpowerShowcase.script())
        checkStepInvariants(run)
        #expect(run.result == .passed, "\(run.outcome.summary)")
        #expect(run.steps.count == 41)

        // Set Up Practice: six archives, one receipt and one grant each, each offering a restore.
        let practice = run.steps.filter { $0.id.rawValue.hasPrefix("practice-") }
        #expect(practice.compactMap(\.receipt).map(\.admitted.operation.target)
            == AccessSuperpowerShowcase.practice.map { .item($0) })
        #expect(practice.allSatisfy { $0.receipt?.undo?.kind == .restoreItem && $0.receipt?.admitted.adapter == .appUI })
        #expect(run.steps.compactMap(\.approval).filter { $0.approvedStep.rawValue.hasPrefix("practice-") }.count == 6)

        // The task's restore, its undo, and the miss.
        let restore = try #require(run.steps.first { $0.id == name("restore-quartz") }?.receipt)
        #expect(restore.summary == "Restored item “Quartz point”.")
        #expect(restore.undo == .archiveItem(id: AccessSuperpowerShowcase.quartz, expected: revision(3)))
        let undo = try #require(run.steps.first { $0.id == name("undo-restore") }?.receipt)
        #expect(undo.admitted.operation == .archiveItem(id: AccessSuperpowerShowcase.quartz, expected: revision(3)))
        let approval = try #require(run.steps.first { $0.id == name("approve-undo-restore") }?.approval)
        #expect(approval.operation == .archiveItem, "the undo archives, so it needs the person's approval")
        let miss = try #require(run.steps.first { $0.id == name("restore-vellum") }?.receipt)
        #expect(miss.conflict == nil && miss.summary == "Restored item “Tracing vellum”.")

        // Reset Practice restored only the practice samples still archived.
        let reset = run.steps.filter { $0.id.rawValue.hasPrefix("reset-practice-") }.compactMap(\.receipt)
        let practiceStillArchived = [AccessSuperpowerShowcase.quartz, AccessSuperpowerShowcase.agate, AccessSuperpowerShowcase.obsidian,
                                     AccessSuperpowerShowcase.cobalt, AccessSuperpowerShowcase.ochre]
        #expect(reset.map(\.admitted.operation.target) == practiceStillArchived.map { .item($0) })

        let state = try #require(run.finalState)
        #expect(state.collections.count == 4 && state.items.count == 13)
        for id in AccessSuperpowerShowcase.practice {
            #expect(state.items.first { $0.id == id }?.isArchived == false, "\(id)")
        }
        let quartz = try #require(state.items.first { $0.id == AccessSuperpowerShowcase.quartz })
        #expect(quartz.revision.rawValue == 5, "archived, restored, archived by the undo, restored by Reset Practice")
        let amber = try #require(state.items.first { $0.id == AccessSuperpowerShowcase.amber })
        #expect(amber.isArchived && amber.namespace == .demo, "a demo sample outside the practice set stays archived")
        let graphite = try #require(state.items.first { $0.id == AccessSuperpowerShowcase.graphite })
        #expect(graphite.isArchived && graphite.namespace == .user && graphite.revision.rawValue == 2, "the person's item is untouched")
        let notes = try #require(state.collections.first { $0.id == AccessSuperpowerShowcase.fieldNotes })
        #expect(notes.namespace == .user && notes.revision == .initial)
    }

    @Test func replaysShareOneFingerprintAcrossRunsAndStores() async throws {
        let script = try AccessSuperpowerShowcase.script()
        let first = await DemoRunner(store: .temporarySQLite).run(script)
        let second = await DemoRunner(store: .temporarySQLite, clock: SuspendingIntervalClock()).run(script)
        let inMemory = await DemoRunner.manual().run(script)
        #expect(first.result == .passed && second.result == .passed && inMemory.result == .passed)
        #expect(ReplayComparison(first, second) == .identical(fingerprint: first.replayFingerprint))
        #expect(ReplayComparison(first, inMemory).isIdentical)
        #expect(first.id != second.id)
    }

    /// Denial: without the person's approval the first practice archive is refused at the commit,
    /// nothing after it runs, and nothing is archived.
    @Test func withoutTheApprovalPracticeArchivesNothing() async throws {
        let temporary = try TemporaryFolder()
        let folder = try AccessSuperpowerShowcase.variant(in: temporary) { object in
            let steps = object["steps"] as? [[String: Any]] ?? []
            object["steps"] = steps.filter { $0["id"] as? String != "approve-practice-quartz" }
        }
        let run = await DemoRunner.manual().run(try DemoScript(folder: folder))
        checkStepInvariants(run)
        #expect(run.result == .failed)
        let archive = try #require(run.steps.first { $0.id == name("practice-quartz") })
        #expect(archive.result == .failed)
        #expect(archive.outcome.detail.contains("no live approval covers this commit-destructive through app-ui"))
        #expect(archive.receipt == nil)
        #expect(run.steps.drop { $0.id != name("practice-quartz") }.dropFirst().allSatisfy { $0.disposition == .skipped })
        #expect(run.finalState?.items.contains { $0.isArchived } == false)
    }

    /// Stale state: a restore at a revision the chart no longer shows is a conflict receipt that
    /// changes nothing, and the replay stops there.
    @Test func aRestoreFromAStaleRevisionIsAConflictThatChangesNothing() async throws {
        let temporary = try TemporaryFolder()
        let folder = try AccessSuperpowerShowcase.variant(in: temporary) { object in
            var steps = object["steps"] as? [[String: Any]] ?? []
            if let index = steps.firstIndex(where: { $0["id"] as? String == "restore-quartz" }) {
                steps[index]["restoreItem"] = ["id": "AF451890-CA80-4DE9-B18B-4007066C9177", "expected": 1]
            }
            object["steps"] = steps
        }
        let run = await DemoRunner.manual().run(try DemoScript(folder: folder))
        checkStepInvariants(run)
        #expect(run.result == .failed)
        let restore = try #require(run.steps.first { $0.id == name("restore-quartz") })
        #expect(restore.result == .failed)
        #expect(restore.outcome.detail.hasPrefix("Conflict, nothing changed"))
        #expect(restore.receipt?.conflict != nil && restore.receipt?.changes.isEmpty == true)
        let quartz = try #require(run.finalState?.items.first { $0.id == AccessSuperpowerShowcase.quartz })
        #expect(quartz.isArchived && quartz.revision.rawValue == 2)
    }

    /// Cancellation: the practice archives that committed before the cancel stay, each with its
    /// receipt; the rest never start.
    @Test func aCancelledPracticeSetUpKeepsOnlyWhatCommitted() async throws {
        let run = await Task {
            await DemoRunner.manual().run(try! AccessSuperpowerShowcase.script()) { record in
                if record.id == name("practice-obsidian") { cancelCurrentTask() }
            }
        }.value
        checkStepInvariants(run)
        #expect(run.result == .notRun)
        let index = try #require(run.steps.firstIndex { $0.id == name("practice-obsidian") })
        #expect(run.steps[...index].allSatisfy { $0.result == .passed })
        #expect(run.steps[(index + 1)...].allSatisfy { $0.disposition == .cancelled && $0.result == .notRun })
        let archived = try #require(run.finalState).items.filter(\.isArchived).map(\.id)
        #expect(Set(archived) == [AccessSuperpowerShowcase.quartz, AccessSuperpowerShowcase.agate, AccessSuperpowerShowcase.obsidian])
    }
}

/// The LAB-035 evidence export: the showcase replayed twice as the app UI, on SQLite with the
/// continuous clock, then exported through the rights and privacy review.
///
/// It writes into a temporary folder that is removed afterwards. To keep the export, name a folder
/// and the build facts; with a folder named, every build fact is required:
///
///     LAB_DEMO_EVIDENCE_DIR=<folder> LAB_SOURCE_REVISION=<sha> LAB_SDK_NAME=macosx27.0 \
///     LAB_XCODE_VERSION=27.0 LAB_XCODE_BUILD=27A266a \
///     swift test --package-path Packages/LabDemo --filter AccessSuperpowerShowcaseEvidence
///
/// `LAB_HOST_EVIDENCE_RECORD=<file>` adds the record the Mac hosted test
/// `AccessSuperpowerHostEvidenceTests` attached, exported from its result bundle, so it passes the
/// same review. It must decode as an `EvidenceRecord` for LAB-035 from the same source revision.
///
/// Keep the export outside `evidence/`, and copy its `records/*.json` into `evidence/LAB-035/`.
@Suite struct AccessSuperpowerShowcaseEvidence {
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
            try #require(host.subject == "LAB-035")
            try #require(host.provenance.sourceRevision == provenance.sourceRevision, "one source revision per export")
            hostArtifacts.append(try .record(host, at: "records/access-superpower-host-four-ways.json", tier: .publicFixture))
        }

        let script = try AccessSuperpowerShowcase.script()
        let runner = DemoRunner(adapter: .appUI, store: .temporarySQLite)
        let runs = [await runner.run(script), await runner.run(script)]
        for run in runs { checkStepInvariants(run) }

        // Nothing is recorded unless both replays passed and agree.
        try #require(runs.allSatisfy { $0.result == .passed })
        try #require(ReplayComparison(runs[0], runs[1]).isIdentical)

        let record = try runs[0].evidenceRecord(
            provenance: provenance,
            check: "Access as a Superpower showcase replayed twice from a clean SQLite store as the app-UI adapter; both replays share one fingerprint"
        )
        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "LAB-035 Access as a Superpower showcase replay",
            artifacts: [
                try .run(runs[0], at: "runs/app-ui-first.json"),
                try .run(runs[1], at: "runs/app-ui-second.json"),
                try .record(record, at: "records/access-superpower-showcase-app-ui.json", tier: .publicFixture),
                try .file("access-superpower/script.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/script.json"),
                try .file("access-superpower/seed.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/seed.json"),
            ] + hostArtifacts,
            untested: [
                "VoiceOver speech, Audio Graph playback, Voice Control, and Full Keyboard Access, by a person, on any device.",
                "A physical iPhone or iPad: no device was used.",
            ],
            provenance: provenance
        ))
        #expect(preview.result == .passed)
        #expect(preview.refused.isEmpty)
        #expect(preview.reviews.count == 5 + hostArtifacts.count)
        #expect(preview.reviews.allSatisfy { $0.tier == .publicFixture && $0.decision == .approved })
        let records = hostArtifacts.isEmpty ? "1 evidence record" : "\(1 + hostArtifacts.count) evidence records"
        #expect(preview.summaryText.hasPrefix("Passed: 2 demo runs and \(records) exported; every one passed."))

        let temporary = try TemporaryFolder()
        let written = try preview.write(into: keep ?? temporary.url, folderName: "lab-035-access-superpower-showcase")
        #expect(temporary.files(below: written) == Set(preview.files.map(\.path)))
        let stored = try JSONDecoder().decode(
            EvidenceRecord.self, from: Data(contentsOf: written.appending(path: "records/access-superpower-showcase-app-ui.json"))
        )
        #expect(stored == record)
        #expect(stored.subject == "LAB-035")
        #expect(stored.path == .fixture)
        #expect(stored.supportedState == .implemented, "a replay never supports device-verified")
        #expect(stored.inputs == script.inputs.map(\.reference))
        #expect(stored.limitations.first == DemoRun.fixtureLimitation)
        #expect(record.outcome.detail.hasPrefix("41 of 41 steps passed."))
        #expect(record.outcome.detail.contains("Adapter app-ui"))
    }
}
