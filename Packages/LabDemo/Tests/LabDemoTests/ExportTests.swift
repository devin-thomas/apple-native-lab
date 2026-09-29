import CryptoKit
import Foundation
@testable import LabDemo
import LabDomain
import LabSupport
import Testing

/// CORE-009 steps 3 and 4: a selected-artifact export with a preview, a rights and privacy
/// review, hashes, provenance, failures, and untested areas, led by the worst result.
@Suite struct ExportTests {
    private let exporter = EvidenceExporter(now: { fixedDate })

    private func failingRun() async throws -> DemoRun {
        await DemoRunner.manual().run(try smallScript([
            DemoStep(name("find-wrong"), try find("brass", expect: [copperCoin])),
            DemoStep(name("find-never"), try find("coin", expect: [copperCoin])),
        ]))
    }

    @Test func thePreviewIsExactlyWhatIsWritten() async throws {
        let folder = try TemporaryFolder()
        let run = await DemoRunner.manual().run(try Showcase.script())
        let record = try run.evidenceRecord(provenance: testProvenance)
        let preview = try exporter.preview(EvidenceExportRequest(
            title: "Showcase replay",
            artifacts: [
                try .run(run, at: "runs/atlas-basics.json"),
                try .record(record, at: "records/atlas-basics.json", tier: .publicFixture),
                try .file("atlas-basics/script.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/script.json"),
                try .file("atlas-basics/seed.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/seed.json"),
            ],
            provenance: testProvenance
        ))
        #expect(preview.files.map(\.path) == [
            "summary.md", "manifest.json", "inputs/script.json", "inputs/seed.json", "records/atlas-basics.json", "runs/atlas-basics.json",
        ])
        let written = try preview.write(into: folder.url, folderName: "export")
        #expect(folder.files(below: written) == Set(preview.files.map(\.path)))
        for file in preview.files {
            #expect(try Data(contentsOf: written.appending(path: file.path)) == file.data, "\(file.path)")
        }
        #expect(try Data(contentsOf: written.appending(path: "inputs/seed.json")) == (try Showcase.data("seed.json")))
        // No temporary folder is left beside the export.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path(percentEncoded: false)) == ["export"])

        // The manifest's hashes are the hashes of the files on disk.
        let manifest = try jsonObject(preview.manifestText)
        let files = try #require(manifest["files"] as? [[String: Any]])
        #expect(files.count == preview.files.count - 1, "every file except the manifest itself")
        for entry in files {
            let path = try #require(entry["path"] as? String)
            let bytes = try Data(contentsOf: written.appending(path: path))
            #expect(entry["sha256"] as? String == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
            #expect(entry["bytes"] as? Int == bytes.count)
        }
        // The exported record decodes as an evidence record, unchanged.
        let decoded = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: written.appending(path: "records/atlas-basics.json")))
        #expect(decoded == record)
    }

    @Test func onlyTheSelectedFilesAreExported() async throws {
        let source = try TemporaryFolder()
        try source.write("chosen\n", to: "notes/chosen.txt")
        try source.write("adjacent\n", to: "notes/adjacent.txt")
        try source.write("nested\n", to: "notes/deeper/nested.txt")
        let preview = try exporter.preview(EvidenceExportRequest(
            title: "One file",
            artifacts: [try .file("notes/chosen.txt", in: source.url, tier: .publicFixture, at: "files/note.txt")],
            provenance: testProvenance
        ))
        let output = try TemporaryFolder()
        let written = try preview.write(into: output.url, folderName: "export")
        #expect(output.files(below: written) == ["summary.md", "manifest.json", "files/note.txt"])
        let everything = try folderText(written)
        #expect(!everything.contains("adjacent") && !everything.contains("nested"))
        #expect(!everything.contains("chosen.txt"), "the source's own name is not recorded")
    }

    @Test func aNonPublicArtifactNeedsAnExplicitRecordedOverride() async throws {
        let source = try TemporaryFolder()
        try source.write("A person's own note.\n", to: "mine.txt")
        try source.write("Not yet classified.\n", to: "unknown.txt")
        let artifacts: [ExportArtifact] = [
            try .file("mine.txt", in: source.url, tier: .userPrivate, at: "files/mine.txt"),
            try .file("unknown.txt", in: source.url, tier: .unclassified, at: "files/unknown.txt"),
        ]

        let refused = try exporter.preview(EvidenceExportRequest(title: "No override", artifacts: artifacts, provenance: testProvenance))
        #expect(refused.files.map(\.path) == ["summary.md", "manifest.json"])
        #expect(refused.refused.map(\.path) == ["files/mine.txt", "files/unknown.txt"])
        #expect(refused.summaryText.contains("`files/mine.txt` (file): user-private, refused"))

        // An override for another tier or another path does not apply.
        let mismatched = try exporter.preview(EvidenceExportRequest(
            title: "Wrong override", artifacts: artifacts,
            overrides: [
                try TierOverride(path: "files/mine.txt", tier: .unclassified, reason: "Wrong tier."),
                try TierOverride(path: "files/other.txt", tier: .userPrivate, reason: "Wrong path."),
            ],
            provenance: testProvenance
        ))
        #expect(mismatched.refused.count == 2)

        let overridden = try exporter.preview(EvidenceExportRequest(
            title: "Override", artifacts: artifacts,
            overrides: [try TierOverride(path: "files/mine.txt", tier: .userPrivate, reason: "The owner chose to share this note.")],
            provenance: testProvenance
        ))
        #expect(overridden.files.map(\.path) == ["summary.md", "manifest.json", "files/mine.txt"])
        #expect(overridden.refused.map(\.path) == ["files/unknown.txt"])
        #expect(overridden.summaryText.contains("user-private, included by override: The owner chose to share this note."))
        let review = try #require(try jsonObject(overridden.manifestText)["review"] as? [[String: Any]])
        let entry = try #require(review.first { $0["path"] as? String == "files/mine.txt" })
        #expect(entry["decision"] as? String == "overridden")
        #expect(entry["reason"] as? String == "The owner chose to share this note.")
        #expect(entry["tier"] as? String == "user-private")
    }

    @Test func sensitiveContentIsRefusedEvenWithAnOverride() async throws {
        #expect(throws: ExportSelectionError.overrideNotAllowed(.sensitive)) {
            try TierOverride(path: "files/secret.txt", tier: .sensitive, reason: "Please.")
        }
        #expect(throws: ExportSelectionError.blankReason) {
            try TierOverride(path: "files/secret.txt", tier: .userPrivate, reason: "  ")
        }
        let source = try TemporaryFolder()
        try source.write("token\n", to: "secret.txt")
        let preview = try exporter.preview(EvidenceExportRequest(
            title: "Sensitive",
            artifacts: [try .file("secret.txt", in: source.url, tier: .sensitive, at: "files/secret.txt")],
            provenance: testProvenance
        ))
        #expect(preview.files.count == 2)
        #expect(preview.refused.first?.decision == .refused(reason: "Sensitive content is never exported, with or without an override."))
    }

    @Test func aPrivateRunIsRefusedLikeAnyOtherArtifact() async throws {
        let run = await DemoRunner.manual().run(try smallScript([], tier: .userPrivate))
        let preview = try exporter.preview(EvidenceExportRequest(title: "Private run", artifacts: [try .run(run)], provenance: testProvenance))
        #expect(preview.files.count == 2)
        #expect(preview.result == .notRun, "nothing evidential was exported")
        #expect(preview.summaryText.hasPrefix("Not run: No demo run or evidence record is in this export."))
    }

    @Test func theManifestCarriesProvenanceEnvironmentFailuresAndUntestedAreas() async throws {
        let passing = await DemoRunner.manual().run(try Showcase.script())
        let failing = try await failingRun()
        let preview = try exporter.preview(EvidenceExportRequest(
            title: "Mixed",
            artifacts: [try .run(passing, at: "runs/passing.json"), try .run(failing, at: "runs/failing.json")],
            untested: ["The Watch host."],
            provenance: BuildProvenance(sourceRevision: "abc1234", sdkName: "macosx27.0", xcodeVersion: "27.0", xcodeBuild: "27A266a")
        ))
        let manifest = try jsonObject(preview.manifestText)
        #expect(manifest["format"] as? String == "native-lab-evidence-export")
        #expect(manifest["exportedAt"] as? String == "2026-09-29T12:00:00Z")
        #expect(manifest["result"] as? String == "failed")
        let provenance = try #require(manifest["provenance"] as? [String: Any])
        #expect(provenance["sourceRevision"] as? String == "abc1234")
        #expect(provenance["xcodeBuild"] as? String == "27A266a")
        #expect(manifest["toolchain"] as? String == "Xcode 27.0 (27A266a), macosx27.0")

        let runs = try #require(manifest["runs"] as? [[String: Any]])
        #expect(runs.count == 2)
        for entry in runs {
            #expect(entry["adapter"] as? String == "app-ui")
            #expect(entry["store"] as? String == "in-memory")
            #expect(entry["timebase"] as? String == "manual-test-clock")
            #expect(entry["measuresRealTime"] as? Bool == false)
            #expect((entry["inputs"] as? [[String: Any]])?.count == 2)
        }

        let failures = try #require(manifest["failures"] as? [[String: Any]])
        #expect(failures.map { $0["step"] as? String } == ["find-wrong", "find-never"])
        #expect(failures.map { $0["result"] as? String } == ["failed", "not-run"])

        let untested = try #require(manifest["untested"] as? [String])
        #expect(untested.first == "The Watch host.")
        #expect(untested.contains(DemoRun.fixtureLimitation))
        #expect(untested.contains("App Intents and Shortcuts entry points: the replay submits every request as the app UI adapter."))
        #expect(untested.contains("Nothing beyond the domain service."))
    }

    @Test func theSummaryStartsWithTheWorstResult() async throws {
        let passing = await DemoRunner.manual().run(try Showcase.script())
        let failing = try await failingRun()
        let blocked = await DemoRunner.manual(store: unopenableStore).run(try Showcase.script())
        let cancelled = await Task {
            cancelCurrentTask()
            return await DemoRunner.manual().run(try! Showcase.script())
        }.value

        func firstLine(_ runs: [DemoRun]) throws -> String {
            let preview = try exporter.preview(EvidenceExportRequest(
                title: "Worst first",
                artifacts: try runs.enumerated().map { try .run($0.element, at: "runs/\($0.offset).json") },
                provenance: testProvenance
            ))
            return String(preview.summaryText.prefix { $0 != "\n" })
        }
        #expect(try firstLine([passing]).hasPrefix("Passed: "))
        #expect(try firstLine([passing, failing, blocked, cancelled]).hasPrefix("Failed: "))
        #expect(try firstLine([passing, cancelled, blocked]).hasPrefix("Blocked: "))
        #expect(try firstLine([passing, cancelled]).hasPrefix("Not run: "))
        #expect(try firstLine([]).hasPrefix("Not run: "))

        // The results list is ordered worst first too.
        let preview = try exporter.preview(EvidenceExportRequest(
            title: "Order",
            artifacts: [try .run(passing, at: "runs/a.json"), try .run(cancelled, at: "runs/b.json"), try .run(failing, at: "runs/c.json")],
            provenance: testProvenance
        ))
        let results = preview.summaryText.components(separatedBy: "\n").filter { $0.hasPrefix("- ") && $0.contains(" — run of ") }
        #expect(results.map { String($0.dropFirst(2).prefix { $0 != ":" }) } == ["Failed", "Not run", "Passed"])
    }

    @Test func anExistingFolderIsNeverReplaced() async throws {
        let output = try TemporaryFolder()
        let run = await DemoRunner.manual().run(try Showcase.script())
        let first = try exporter.preview(EvidenceExportRequest(title: "First", artifacts: [try .run(run)], provenance: testProvenance))
        let second = try exporter.preview(EvidenceExportRequest(title: "Second", artifacts: [], provenance: testProvenance))
        let written = try first.write(into: output.url, folderName: "export")
        #expect(throws: EvidenceExportError.confinement(.finishing, .alreadyExists)) {
            try second.write(into: output.url, folderName: "export")
        }
        #expect(try String(contentsOf: written.appending(path: "summary.md"), encoding: .utf8) == first.summaryText)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.url.path(percentEncoded: false)) == ["export"])
    }

    @Test func aRunCannotBeReadBackAsEvidence() throws {
        // DemoRun and DemoStepRecord have no decoder: an export holds what this process ran.
        #expect(!(DemoRun.self is any Decodable.Type))
        #expect(!(DemoStepRecord.self is any Decodable.Type))
        #expect(!(PerformanceClaim.self is any Decodable.Type))
    }

    private func folderText(_ folder: URL) throws -> String {
        var text = ""
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            text += url.path(percentEncoded: false) + "\n"
            if let data = try? Data(contentsOf: url) { text += String(decoding: data, as: UTF8.self) }
        }
        return text
    }
}
