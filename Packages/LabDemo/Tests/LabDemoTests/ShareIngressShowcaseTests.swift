import CryptoKit
import Foundation
@testable import LabDemo
import LabDomain
import LabStore
import LabSupport
import Testing

/// `Fixtures/showcase/share-ingress/`: LAB-007's fixture interaction after review, replayed from a
/// clean store. The intake and the review happen before the first change, so this replay starts at
/// Reset Demo and covers what the review commits: a collection of the person's own, the two
/// additions a person's Add makes, and a second Reset Demo that leaves them alone.
enum ShareIngressShowcase {
    static let folder = Showcase.fixtures.appending(path: "share-ingress", directoryHint: .isDirectory)
    static let appSeed = Showcase.repositoryRoot.appending(path: "Fixtures/demo/seed.json")

    static func script() throws -> DemoScript {
        try DemoScript(folder: folder)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: name))
    }

    static let fieldNotes = CollectionID(rawValue: UUID(uuidString: "D246FD2A-EFE5-4FC5-9E15-7D3D365C6A5B")!)
    static let note = ItemID(rawValue: UUID(uuidString: "DA70B1D5-DC5B-8106-93B1-C22AD3032F05")!)
    static let link = ItemID(rawValue: UUID(uuidString: "DFE178D0-0518-8AD4-A1E8-772CCDA3DF75")!)
    static let pigments = CollectionID(rawValue: UUID(uuidString: "A40194B3-5E91-4C5C-AE02-CF703BE23224")!)

    /// The intake files whose hashes a record names. The two text files can also be exported.
    static let intakeFiles = ["intake/harbor-walk.txt", "intake/gull-count.txt", "intake/harbor-sketch.png", "intake/tide-clip.mov"]

    static func variant(in temporary: TemporaryFolder, _ change: (inout [String: Any]) -> Void) throws -> URL {
        let copy = temporary.url.appending(path: "share-ingress", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: folder, to: copy)
        try rewriteScript(in: copy, change)
        return copy
    }
}

/// LAB-007-B step 1: replay the fixture interaction from a clean state. Fixture path: it proves
/// the operations a review commits, not the intake, a view, a share sheet, or a device.
@Suite struct ShareIngressShowcaseTests {
    @Test func theShowcaseSeedIsTheAppsDemoSeedByteForByte() throws {
        #expect(try ShareIngressShowcase.data("seed.json") == (try Data(contentsOf: ShareIngressShowcase.appSeed)))
    }

    @Test func theShowcaseLoadsWithTheHashesOfItsExactBytes() throws {
        let script = try ShareIngressShowcase.script()
        func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        #expect(script.subject == "LAB-007")
        #expect(script.dataTier == .publicFixture)
        #expect(script.seed.collections.count == 3 && script.seed.items.count == 12)
        #expect(script.inputs.map(\.reference) == [
            "script:share-ingress@sha256:\(hex(try ShareIngressShowcase.data("script.json")))",
            "seed:share-ingress@sha256:\(hex(try Data(contentsOf: ShareIngressShowcase.appSeed)))",
        ])
    }

    @Test func theReviewedAdditionsPassFromACleanStoreAndResetLeavesThemAlone() async throws {
        let run = await DemoRunner(store: .temporarySQLite).run(try ShareIngressShowcase.script())
        checkStepInvariants(run)
        #expect(run.result == .passed, "\(run.outcome.summary)")
        #expect(run.steps.count == 12)

        let state = try #require(run.finalState)
        #expect(state.collections.count == 4 && state.items.count == 14)
        let fieldNotes = try #require(state.collections.first { $0.id == ShareIngressShowcase.fieldNotes })
        #expect(fieldNotes.namespace == .user && fieldNotes.title.value == "Field notes")
        let note = try #require(state.items.first { $0.id == ShareIngressShowcase.note })
        #expect(note.namespace == .user && note.collectionID == ShareIngressShowcase.fieldNotes)
        #expect(note.title.value == "Harbor walk")
        #expect(note.note.value == String(decoding: try ShareIngressShowcase.data("intake/harbor-walk.txt"), as: UTF8.self))
        #expect(note.revision == .initial && !note.isArchived)
        let link = try #require(state.items.first { $0.id == ShareIngressShowcase.link })
        #expect(link.title.value == "example.org" && link.note.value == "https://example.org/tide-tables")
        #expect(link.revision == .initial)

        // Each addition was approved for exactly one new item in Field notes, as the Add issues it.
        for (approve, add) in [("approve-add-note", "add-note"), ("approve-add-link", "add-link")] {
            let approval = try #require(run.steps.first { $0.id == name(approve) }?.approval)
            #expect(approval.approvedStep == name(add))
            #expect(approval.operation == .createItem && approval.adapter == .appUI)
            #expect(approval.target == "new item in \(ShareIngressShowcase.fieldNotes)")
            let receipt = try #require(run.steps.first { $0.id == name(add) }?.receipt)
            #expect(receipt.status == .committed && receipt.admitted.adapter == .appUI)
            #expect(receipt.changes.count == 1 && receipt.removed.isEmpty)
        }

        // The second Reset Demo found the demo as seeded: it changed and removed nothing.
        let reset = try #require(run.steps.first { $0.id == name("reset-again") }?.receipt)
        #expect(reset.changes.isEmpty && reset.removed.isEmpty)
        #expect(reset.summary.hasPrefix("The demo already matched"))
    }

    @Test func replaysShareOneFingerprintAcrossRunsAndStores() async throws {
        let script = try ShareIngressShowcase.script()
        let first = await DemoRunner(store: .temporarySQLite).run(script)
        let second = await DemoRunner(store: .temporarySQLite, clock: SuspendingIntervalClock()).run(script)
        let inMemory = await DemoRunner.manual().run(script)
        #expect(first.result == .passed && second.result == .passed && inMemory.result == .passed)
        #expect(ReplayComparison(first, second) == .identical(fingerprint: first.replayFingerprint))
        #expect(ReplayComparison(first, inMemory).isIdentical)
        #expect(first.id != second.id)
    }

    /// Denial: a demo collection cannot take an import. The addition is refused at the commit with
    /// no receipt, nothing after it starts, and no item is stored.
    @Test func anImportCannotBeAddedToADemoCollection() async throws {
        let temporary = try TemporaryFolder()
        let folder = try ShareIngressShowcase.variant(in: temporary) { object in
            var steps = object["steps"] as? [[String: Any]] ?? []
            for index in steps.indices where steps[index]["id"] as? String == "add-note" {
                var create = steps[index]["createItem"] as? [String: Any] ?? [:]
                create["collection"] = ShareIngressShowcase.pigments.rawValue.uuidString
                steps[index]["createItem"] = create
            }
            object["steps"] = steps
        }
        let run = await DemoRunner.manual().run(try DemoScript(folder: folder))
        checkStepInvariants(run)
        #expect(run.result == .failed)
        let add = try #require(run.steps.first { $0.id == name("add-note") })
        #expect(add.result == .failed && add.receipt == nil)
        #expect(add.outcome.detail.contains("is a demo collection, which holds only seed samples"))
        #expect(run.steps.drop { $0.id != name("add-note") }.dropFirst().allSatisfy { $0.disposition == .skipped })
        #expect(run.finalState?.items.contains { $0.id == ShareIngressShowcase.note } == false)
        #expect(run.finalState?.items.count == 12)
    }

    /// Denial: composed as the model-tool adapter, the replay can change nothing, not even the
    /// first Reset Demo, and nothing is stored.
    @Test func aModelToolCanAddNothing() async throws {
        let run = await DemoRunner.manual(adapter: .modelTool).run(try ShareIngressShowcase.script())
        checkStepInvariants(run)
        #expect(run.result == .failed)
        #expect(run.steps.first { $0.result == .failed }?.id == name("approve-reset"))
        #expect(run.finalState?.items.isEmpty == true && run.finalState?.collections.isEmpty == true)
    }

    /// Cancellation: the note committed before the cancel stays; the link is never added.
    @Test func aCancelledReplayAddsNothingAfterTheCancel() async throws {
        let run = await Task {
            await DemoRunner.manual().run(try! ShareIngressShowcase.script()) { record in
                if record.id == name("add-note") { cancelCurrentTask() }
            }
        }.value
        checkStepInvariants(run)
        #expect(run.result == .notRun)
        let index = try #require(run.steps.firstIndex { $0.id == name("add-note") })
        #expect(run.steps[...index].allSatisfy { $0.result == .passed })
        #expect(run.steps[(index + 1)...].allSatisfy { $0.disposition == .cancelled && $0.result == .notRun })
        let state = try #require(run.finalState)
        #expect(state.items.contains { $0.id == ShareIngressShowcase.note })
        #expect(!state.items.contains { $0.id == ShareIngressShowcase.link })
    }
}

/// The LAB-007 evidence export: the showcase replayed twice as the app UI on SQLite with the
/// continuous clock, then exported through the rights and privacy review with its script, seed,
/// and the two text files of its intake.
///
/// It writes into a temporary folder that is removed afterwards. To keep the export, name a folder
/// and the build facts; with a folder named, every build fact is required:
///
///     LAB_DEMO_EVIDENCE_DIR=<folder> LAB_SOURCE_REVISION=<sha> LAB_SDK_NAME=macosx27.0 \
///     LAB_XCODE_VERSION=27.0 LAB_XCODE_BUILD=27A266a \
///     swift test --package-path Packages/LabDemo --filter ShareIngressShowcaseEvidence
///
/// `LAB_HOST_EVIDENCE_RECORD=<file>` adds the record the Mac hosted test
/// `ShareIngressHostEvidenceTests` attached, exported from its result bundle, so it passes the
/// same review. It must decode as an `EvidenceRecord` for LAB-007 from the same source revision.
///
/// Keep the export outside `evidence/`, and copy its `records/*.json` into `evidence/LAB-007/`.
@Suite struct ShareIngressShowcaseEvidence {
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
        var hostArtifacts: [ExportArtifact] = []
        if let path = environment["LAB_HOST_EVIDENCE_RECORD"] {
            let host = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: URL(filePath: path)))
            try #require(host.subject == "LAB-007")
            try #require(host.provenance.sourceRevision == provenance.sourceRevision, "one source revision per export")
            hostArtifacts.append(try .record(host, at: "records/share-ingress-host-intake-to-receipt.json", tier: .publicFixture))
        }

        let script = try ShareIngressShowcase.script()
        let runner = DemoRunner(adapter: .appUI, store: .temporarySQLite)
        let runs = [await runner.run(script), await runner.run(script)]
        for run in runs { checkStepInvariants(run) }

        // Nothing is recorded unless both replays passed and agree.
        try #require(runs.allSatisfy { $0.result == .passed })
        try #require(ReplayComparison(runs[0], runs[1]).isIdentical)

        let record = try runs[0].evidenceRecord(
            provenance: provenance,
            check: "Share Ingress showcase replayed twice from a clean SQLite store as the app-UI adapter, the adapter a pasted import is added as; both replays share one fingerprint"
        )
        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "LAB-007 Share Ingress showcase replay",
            artifacts: [
                try .run(runs[0], at: "runs/app-ui-first.json"),
                try .run(runs[1], at: "runs/app-ui-second.json"),
                try .record(record, at: "records/share-ingress-showcase-app-ui.json", tier: .publicFixture),
                try .file("share-ingress/script.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/script.json"),
                try .file("share-ingress/seed.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/seed.json"),
                try .file("share-ingress/intake/harbor-walk.txt", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/intake/harbor-walk.txt"),
                try .file("share-ingress/intake/gull-count.txt", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/intake/gull-count.txt"),
            ] + hostArtifacts,
            untested: [
                "The share extension and App Group staging on a device: a free Personal Team cannot sign App Groups.",
                "A physical iPhone or iPad: no device was used.",
            ],
            provenance: provenance
        ))
        #expect(preview.result == .passed)
        #expect(preview.refused.isEmpty)
        #expect(preview.reviews.count == 7 + hostArtifacts.count)
        #expect(preview.reviews.allSatisfy { $0.tier == .publicFixture && $0.decision == .approved })
        let records = hostArtifacts.isEmpty ? "1 evidence record" : "\(1 + hostArtifacts.count) evidence records"
        #expect(preview.summaryText.hasPrefix("Passed: 2 demo runs and \(records) exported; every one passed."), "\(preview.summaryText)")

        let temporary = try TemporaryFolder()
        let written = try preview.write(into: keep ?? temporary.url, folderName: "lab-007-share-ingress-showcase")
        #expect(temporary.files(below: written) == Set(preview.files.map(\.path)))
        let stored = try JSONDecoder().decode(
            EvidenceRecord.self, from: Data(contentsOf: written.appending(path: "records/share-ingress-showcase-app-ui.json"))
        )
        #expect(stored == record)
        #expect(stored.subject == "LAB-007")
        #expect(stored.path == .fixture)
        #expect(stored.supportedState == .implemented, "a replay never supports device-verified")
        #expect(stored.inputs == script.inputs.map(\.reference))
        #expect(stored.limitations.first == DemoRun.fixtureLimitation)
        #expect(record.outcome.detail.contains("12 of 12 steps passed"))
        #expect(record.outcome.detail.contains("Adapter app-ui"))
    }
}

/// A run of LAB-007 observed in a simulator through a UI-test harness, as the harness recorded it.
///
/// The facts are read from a file kept outside the repository, the provenance from the Info.plist
/// of the app the harness installed, and `EvidenceRecord` validates the result, so the record
/// carries no simulator identifier. A simulator record supports `implemented` at most.
struct SimulatorRunFacts: Codable {
    /// The record's file name in the export, without `.json`.
    let name: String
    let subject: String
    let check: String
    let observedAt: Date
    let platform: String
    let deviceClass: String
    let osVersion: String
    let buildInfoPlist: String
    let inputs: [String]
    let steps: [String]
    let result: RunResult
    let observed: String
    let limitations: [String]

    static func load(_ url: URL) throws -> SimulatorRunFacts {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SimulatorRunFacts.self, from: Data(contentsOf: url))
    }

    func record() throws -> EvidenceRecord {
        let info = try #require(NSDictionary(contentsOf: URL(filePath: buildInfoPlist)) as? [String: Any], "the build's Info.plist")
        guard let platform = LabPlatform(rawValue: platform) else { throw EvidenceError.unknownPlatform(platform) }
        return try EvidenceRecord(
            subject: subject,
            check: check,
            date: observedAt,
            provenance: BuildProvenance(infoDictionary: info),
            execution: .simulator(SimulatedDevice(platform: platform, deviceClass: deviceClass, osVersion: osVersion)),
            inputs: inputs,
            steps: steps,
            outcome: RunOutcome(result, detail: observed),
            limitations: limitations
        )
    }

    var exportPath: String { "records/\(name).json" }
}

@Suite struct ShareIngressSimulatorEvidence {
    private func facts(plist: URL, result: RunResult = .passed) -> SimulatorRunFacts {
        SimulatorRunFacts(
            name: "simulator-run", subject: "LAB-007", check: "A share in the simulator", observedAt: fixedDate,
            platform: "iOS", deviceClass: "iPhone 17 Pro", osVersion: "27.0 (24A434)", buildInfoPlist: plist.path(percentEncoded: false),
            inputs: ["intake:harbor-sketch.png@sha256:00"], steps: ["Share it."], result: result, observed: "Observed.",
            limitations: ["Simulator only."]
        )
    }

    private func infoPlist(in folder: TemporaryFolder) throws -> URL {
        let info: [String: Any] = [
            "LabSourceRevision": "0000000", "DTSDKName": "iphonesimulator27.0", "DTXcode": "2700", "DTXcodeBuild": "27A266a",
            "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1", "LabBuildProfile": "SystemSurfaces", "MinimumOSVersion": "26.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        return try folder.write(data, to: "Info.plist")
    }

    /// The generator: a simulator record keeps its path, supports `implemented` at most, and is
    /// never device proof; a public fixture run needs no override to leave.
    @Test func aSimulatorRunIsNeverDeviceProof() throws {
        let folder = try TemporaryFolder()
        let record = try facts(plist: try infoPlist(in: folder)).record()
        #expect(record.path == .simulator)
        #expect(record.supportedState == .implemented)
        #expect(record.provenance.buildProfile == "SystemSurfaces")
        #expect(throws: PromotionError.notPhysical(.simulator)) { try DeviceProof(record) }
        let preview = try EvidenceExporter(now: { fixedDate }).preview(EvidenceExportRequest(
            title: "LAB-007", artifacts: [try .record(record, at: "records/simulator-run.json", tier: .publicFixture)],
            provenance: record.provenance
        ))
        #expect(preview.refused.isEmpty && preview.result == .passed)
    }

    /// Writes an observed simulator run's record through the review. Runs only when both are named:
    ///
    ///     LAB_007_SIMULATOR_RUN_FACTS=<facts.json> LAB_DEMO_EVIDENCE_DIR=<folder> \
    ///     swift test --package-path Packages/LabDemo --filter ShareIngressSimulatorEvidence
    ///
    /// Keep the facts and the export outside the repository, and copy the exported record into
    /// `evidence/LAB-007/`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LAB_007_SIMULATOR_RUN_FACTS"] != nil))
    func theObservedRunExportsThroughTheReview() throws {
        let environment = ProcessInfo.processInfo.environment
        let facts = try SimulatorRunFacts.load(URL(filePath: try #require(environment["LAB_007_SIMULATOR_RUN_FACTS"])))
        let folder = URL(filePath: try #require(environment["LAB_DEMO_EVIDENCE_DIR"]), directoryHint: .isDirectory)
        let record = try facts.record()
        try #require(record.subject == "LAB-007")
        try #require(record.provenance.sourceRevision != "unknown" && record.provenance.xcodeBuild != "unknown")
        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "LAB-007 run in the iOS simulator",
            artifacts: [try .record(record, at: facts.exportPath, tier: .publicFixture)],
            untested: ["A physical iPhone or iPad: no device was used."],
            provenance: record.provenance
        ))
        try #require(preview.refused.isEmpty)
        let written = try preview.write(into: folder, folderName: "\(facts.name)-export")
        let stored = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: written.appending(path: facts.exportPath)))
        #expect(stored == record)
    }
}
