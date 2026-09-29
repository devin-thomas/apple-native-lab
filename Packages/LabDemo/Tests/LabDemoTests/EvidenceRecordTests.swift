import Foundation
@testable import LabDemo
import LabDomain
import LabSupport
import Testing

/// A run becomes an `EvidenceRecord` with the CORE-007 vocabulary: fixture path, the worst result,
/// the hashed inputs, and every limitation.
@Suite struct EvidenceRecordTests {
    @Test func aPassingReplayIsFixtureEvidenceForImplementedAtMost() async throws {
        let run = await DemoRunner.manual().run(try Showcase.script())
        let record = try run.evidenceRecord(provenance: testProvenance)
        #expect(record.subject == "CORE-009")
        #expect(record.check == "Replay of demo script atlas-basics")
        #expect(record.date == fixedDate)
        #expect(record.execution == .fixture)
        #expect(record.result == .passed)
        #expect(record.supportedState == .implemented)
        #expect(throws: PromotionError.self) { try ImplementationState.implemented.promoted(to: .deviceVerified, by: record) }
        #expect(record.inputs == run.script.inputs.map(\.reference))
        #expect(record.inputs.allSatisfy { $0.contains("@sha256:") })
        #expect(record.steps.count == 11)
        #expect(record.steps[4] == "rename-glass: Rename the sea glass sample and rewrite its note.")
        #expect(record.outcome.detail.contains("11 of 11 steps passed"))
        #expect(record.outcome.detail.contains(run.replayFingerprint.hex))
        #expect(record.limitations.first == DemoRun.fixtureLimitation)
        #expect(record.limitations.count == 1 + run.script.untested.count)

        let encoded = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(EvidenceRecord.self, from: encoded) == record)
    }

    @Test func aFailingReplayRecordsItsFailureAndUnrunSteps() async throws {
        let run = await DemoRunner.manual().run(try smallScript([
            DemoStep(name("find-wrong"), try find("brass", expect: [])),
            DemoStep(name("find-never"), try find("coin", expect: [copperCoin])),
        ]))
        let record = try run.evidenceRecord(provenance: testProvenance)
        #expect(record.result == .failed)
        #expect(record.supportedState == nil)
        #expect(record.logRow.contains("| Failed (Fixture): "))
        #expect(record.limitations.contains { $0.hasPrefix("Step find-wrong failed: ") })
        #expect(record.limitations.contains { $0.hasPrefix("Step find-never not-run: ") })
    }
}

/// The showcase end to end: two replays on SQLite with the continuous clock, their record, the
/// inputs, and two performance claims from the first run, exported and written.
///
/// It writes into a temporary folder that is removed afterwards. To keep the export for the
/// evidence desk, name a folder and the build facts:
///
///     LAB_DEMO_EVIDENCE_DIR=<folder> LAB_SOURCE_REVISION=<sha> LAB_SDK_NAME=macosx27.0 \
///     LAB_XCODE_VERSION=27.0 LAB_XCODE_BUILD=27A266a swift test --filter ShowcaseEvidence
@Suite struct ShowcaseEvidence {
    @Test func theShowcaseExportsEndToEnd() async throws {
        let environment = ProcessInfo.processInfo.environment
        let provenance = BuildProvenance(
            sourceRevision: environment["LAB_SOURCE_REVISION"] ?? "unknown",
            sdkName: environment["LAB_SDK_NAME"] ?? "unknown",
            xcodeVersion: environment["LAB_XCODE_VERSION"] ?? "unknown",
            xcodeBuild: environment["LAB_XCODE_BUILD"] ?? "unknown"
        )
        let script = try Showcase.script()
        let runner = DemoRunner(store: .temporarySQLite)
        let first = await runner.run(script)
        let second = await runner.run(script)
        checkStepInvariants(first)
        checkStepInvariants(second)
        #expect(first.result == .passed && second.result == .passed)
        #expect(ReplayComparison(first, second).isIdentical)

        let record = try first.evidenceRecord(provenance: provenance, check: "Showcase atlas-basics replayed twice on SQLite")
        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "CORE-009 showcase replay",
            artifacts: [
                try .run(first, at: "runs/first.json"),
                try .run(second, at: "runs/second.json"),
                try .record(record, at: "records/atlas-basics.json", tier: .publicFixture),
                try .file("atlas-basics/script.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/script.json"),
                try .file("atlas-basics/seed.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/seed.json"),
            ],
            claims: [try PerformanceClaim(run: first), try PerformanceClaim(run: first, step: name("reset"))],
            untested: ["Any host app: no view, intent, or extension called the runner."],
            provenance: provenance
        ))
        #expect(preview.result == .passed)
        #expect(preview.refused.isEmpty)

        let temporary = try TemporaryFolder()
        let folder = environment["LAB_DEMO_EVIDENCE_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) } ?? temporary.url
        let written = try preview.write(into: folder, folderName: "core-009-showcase")
        #expect(temporary.files(below: written) == Set(preview.files.map(\.path)))
        let stored = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: written.appending(path: "records/atlas-basics.json")))
        #expect(stored == record)
        #expect(stored.supportedState == .implemented)
    }
}
