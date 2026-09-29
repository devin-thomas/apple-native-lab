import Foundation
import LabDomain
import LabSupport

/// Exactly what an evidence export will write, computed before anything is written.
///
/// `files` is the complete allowlist: every path and every byte. Show it to the person, then call
/// `write(into:folderName:)`, which writes those bytes and nothing else.
public struct EvidenceExportPreview: Sendable {
    public struct File: Sendable, Equatable {
        let stagedPath: StagedPath
        public let data: Data
        public let sha256: ContentDigest
        /// `summary`, `manifest`, or an artifact kind.
        public let kind: String
        /// The declared tier of an artifact; `nil` for the summary and manifest, which the
        /// exporter writes from reviewed content only.
        public let tier: DataTier?

        init(path: StagedPath, data: Data, kind: String, tier: DataTier?) {
            stagedPath = path
            self.data = data
            sha256 = ContentDigest.sha256(data)
            self.kind = kind
            self.tier = tier
        }

        /// The file's path inside the export folder.
        public var path: String { stagedPath.value }
    }

    /// Every file, in write order: `summary.md`, `manifest.json`, then the artifacts by path.
    public let files: [File]
    /// The review of every selected artifact, including the refused ones.
    public let reviews: [ArtifactReview]
    /// The worst result among the exported runs and records; `not-run` when there are none.
    public let result: RunResult

    public var summaryText: String { String(decoding: files[0].data, as: UTF8.self) }
    public var manifestText: String { String(decoding: files[1].data, as: UTF8.self) }
    public var refused: [ArtifactReview] { reviews.filter(\.isRefused) }

    /// Writes the previewed files into a new folder named `folderName` inside `parent`.
    ///
    /// The files are written to a temporary folder beside the destination with exclusive creates
    /// that follow no link. The folder is then checked: it must hold exactly the previewed paths,
    /// with the previewed bytes, and nothing else. Only then is it renamed into place with an
    /// exclusive rename, so an existing folder is never replaced and a failed export leaves nothing
    /// behind. Returns the new folder.
    public func write(into parent: URL, folderName: String) throws(EvidenceExportError) -> URL {
        guard let name = try? StagedPath(folderName), name.components.count == 1, !folderName.hasPrefix(".") else {
            throw .invalidFolderName
        }
        let parentPath: String
        do { parentPath = try ConfinedFile.resolvedRoot(parent) } catch { throw .confinement(.destination, error) }
        let destination = parentPath + "/" + name.value
        let temporary = parentPath + "/.\(name.value).partial-\(UUID().uuidString)"
        do { try ConfinedFile.makeFolder(atPath: temporary) } catch { throw .confinement(.destination, error) }

        do {
            for file in files {
                do { try ConfinedFile.writeNew(file.data, to: file.stagedPath, belowFolder: temporary) } catch {
                    throw EvidenceExportError.confinement(.writing, error)
                }
            }
            try verify(folder: temporary)
            do { try ConfinedFile.moveExclusively(temporary, to: destination) } catch {
                throw EvidenceExportError.confinement(.finishing, error)
            }
        } catch let error as EvidenceExportError {
            try? FileManager.default.removeItem(atPath: temporary)
            throw error
        } catch {
            try? FileManager.default.removeItem(atPath: temporary)
            throw .verificationFailed
        }
        return URL(filePath: destination, directoryHint: .isDirectory)
    }

    /// The folder holds exactly the previewed files, byte for byte, and only the folders they need.
    func verify(folder: String) throws(EvidenceExportError) {
        let expectedFiles = Set(files.map(\.path))
        var expectedFolders = Set<String>()
        for file in files {
            let parts = file.stagedPath.components.dropLast()
            for count in parts.indices {
                expectedFolders.insert(parts[...count].joined(separator: "/"))
            }
        }
        let inventory = ConfinedFile.inventory(below: folder)
        var seenFiles = Set<String>()
        for entry in inventory {
            let path = entry.path.precomposedStringWithCanonicalMapping
            if entry.isFolder {
                guard expectedFolders.contains(path) else { throw .verificationFailed }
            } else {
                guard entry.isRegularFile, expectedFiles.contains(path) else { throw .verificationFailed }
                seenFiles.insert(path)
            }
        }
        guard seenFiles == expectedFiles else { throw .verificationFailed }
        let root = URL(filePath: folder, directoryHint: .isDirectory)
        for file in files {
            guard let written = try? ConfinedFile.read(file.stagedPath, under: root, maximumBytes: file.data.count),
                  ContentDigest.sha256(written) == file.sha256 else { throw .verificationFailed }
        }
    }
}

// MARK: - Content

/// The reviewed content of one export, rendered as its summary and manifest.
struct ExportContent {
    let title: String
    let exportedAt: Date
    let provenance: BuildProvenance
    let runs: [(path: String, run: DemoRun)]
    let records: [(path: String, record: EvidenceRecord)]
    let reviews: [ArtifactReview]
    let claims: [ClaimEntry]
    let requestUntested: [String]

    /// One exported run or record and its outcome.
    struct Item {
        let label: String
        let path: String
        let outcome: RunOutcome
    }

    var items: [Item] {
        runs.map { Item(label: "run of `\($0.run.script.id)` (\($0.run.id))", path: $0.path, outcome: $0.run.outcome) }
            + records.map { Item(label: "record “\($0.record.check)” (\($0.record.subject))", path: $0.path, outcome: $0.record.outcome) }
    }

    /// The worst result among the exported runs and records. With neither, nothing ran.
    var result: RunResult { RunResult.combining(items.map(\.outcome.result)) }

    var headline: RunOutcome {
        let items = self.items
        guard !items.isEmpty else {
            return RunOutcome(.notRun, detail: "No demo run or evidence record is in this export.")
        }
        let notPassed = items.filter { $0.outcome.result != .passed }.count
        let runs = self.runs.count == 1 ? "1 demo run" : "\(self.runs.count) demo runs"
        let records = self.records.count == 1 ? "1 evidence record" : "\(self.records.count) evidence records"
        let detail = notPassed == 0
            ? "\(runs) and \(records) exported; every one passed."
            : "\(runs) and \(records) exported; \(notPassed) did not pass."
        return RunOutcome(result, detail: detail)
    }

    private static func severity(_ result: RunResult) -> Int {
        switch result {
        case .failed: 0
        case .blocked: 1
        case .notRun: 2
        case .passed: 3
        }
    }

    var itemsWorstFirst: [Item] {
        items.enumerated()
            .sorted { (Self.severity($0.element.outcome.result), $0.offset) < (Self.severity($1.element.outcome.result), $1.offset) }
            .map(\.element)
    }

    var failures: [FailureEntry] {
        var entries: [FailureEntry] = []
        for (path, run) in runs {
            for step in run.steps where step.result != .passed {
                entries.append(FailureEntry(
                    source: path, step: step.id.rawValue, result: step.result, detail: step.outcome.detail
                ))
            }
        }
        for (path, record) in records where record.result != .passed {
            entries.append(FailureEntry(source: path, step: nil, result: record.result, detail: record.outcome.detail))
        }
        return entries.enumerated()
            .sorted { (Self.severity($0.element.result), $0.offset) < (Self.severity($1.element.result), $1.offset) }
            .map(\.element)
    }

    var untested: [String] {
        var seen = Set<String>()
        var list: [String] = []
        func add(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, seen.insert(trimmed).inserted { list.append(trimmed) }
        }
        requestUntested.forEach(add)
        if !runs.isEmpty { add(DemoRun.fixtureLimitation) }
        for (_, run) in runs { run.script.untested.forEach(add) }
        for (_, record) in records { record.limitations.forEach(add) }
        return list
    }

    // MARK: Summary

    func summaryText(files: [EvidenceExportPreview.File]) -> String {
        var lines = [headline.summary, "", "# \(title)", ""]
        lines.append(
            "Exported \(exportedAt.formatted(Date.ISO8601FormatStyle())) as \(EvidenceExporter.format) version \(EvidenceExporter.formatVersion). "
                + "Source revision \(provenance.sourceRevision); \(provenance.toolchainSummary); build profile \(provenance.buildProfile)."
        )
        lines += ["", "## Results, worst first", ""]
        if items.isEmpty { lines.append("- Not run: nothing was exported.") }
        for item in itemsWorstFirst {
            lines.append("- \(item.outcome.summary) — \(item.label), `\(item.path)`.")
        }
        for (path, run) in runs {
            lines.append(
                "- `\(path)`: adapter \(run.adapter.rawValue), store \(run.environment.store), timebase \(run.environment.timebase.rawValue), replay fingerprint `\(run.replayFingerprint.hex)`."
            )
        }

        lines += ["", "## Failures and steps that did not run", ""]
        let failures = self.failures
        if failures.isEmpty { lines.append("- None.") }
        for failure in failures {
            let step = failure.step.map { " step `\($0)`" } ?? ""
            lines.append("- \(failure.result.title): `\(failure.source)`\(step): \(failure.detail)")
        }

        lines += ["", "## Not tested", ""]
        let untested = self.untested
        if untested.isEmpty { lines.append("- Nothing was declared.") }
        lines += untested.map { "- \($0)" }

        lines += ["", "## Performance", ""]
        if claims.isEmpty {
            lines.append("- No performance claim. A number appears here only for a step or run that passed on a real-time clock, in a run exported with it.")
        }
        lines += claims.map { "- \($0.sentence)" }

        lines += ["", "## Rights and privacy review", ""]
        if reviews.isEmpty { lines.append("- Nothing was selected.") }
        lines += reviews.map { "- `\($0.path)` (\($0.kind.rawValue)): \($0.summary)" }

        lines += ["", "## Files", "", "| File | SHA-256 | Bytes |", "|---|---|---|"]
        lines += files.map { "| `\($0.path)` | `\($0.sha256.hex)` | \($0.data.count) |" }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Manifest

    func manifest(files: [EvidenceExportPreview.File]) -> Manifest {
        Manifest(
            format: EvidenceExporter.format,
            formatVersion: EvidenceExporter.formatVersion,
            title: title,
            exportedAt: exportedAt,
            result: result,
            summary: headline.summary,
            provenance: provenance,
            toolchain: provenance.toolchainSummary,
            runs: runs.map { RunEntry(path: $0.path, run: $0.run) },
            records: records.map { RecordEntry(path: $0.path, record: $0.record) },
            files: files.map { FileEntry(path: $0.path, kind: $0.kind, tier: $0.tier, sha256: $0.sha256.hex, bytes: $0.data.count) },
            review: reviews.map(ReviewEntry.init),
            failures: failures,
            untested: untested,
            performance: claims,
            notes: [
                "Every file listed here was previewed before it was written, and the export folder holds exactly these files and this manifest.",
                "Only public-fixture artifacts are exported without an override; sensitive artifacts are never exported.",
                "Source files are exported under names the person chose; their original paths are not recorded.",
                "Performance numbers appear only as claims linked to an exported run that measured them on a real-time clock.",
            ]
        )
    }

    struct Manifest: Encodable {
        let format: String
        let formatVersion: Int
        let title: String
        let exportedAt: Date
        let result: RunResult
        let summary: String
        let provenance: BuildProvenance
        let toolchain: String
        let runs: [RunEntry]
        let records: [RecordEntry]
        let files: [FileEntry]
        let review: [ReviewEntry]
        let failures: [FailureEntry]
        let untested: [String]
        let performance: [ClaimEntry]
        let notes: [String]
    }

    struct RunEntry: Encodable {
        let artifact: String
        let run: DemoRunID
        let script: DemoName
        let subject: String
        let adapter: AdapterKind
        let store: String
        let timebase: Timebase
        let timebaseDeclaration: String
        let measuresRealTime: Bool
        let result: RunResult
        let replayFingerprint: String
        let inputs: [DemoInput]

        init(path: String, run: DemoRun) {
            artifact = path
            self.run = run.id
            script = run.script.id
            subject = run.script.subject
            adapter = run.adapter
            store = run.environment.store
            timebase = run.environment.timebase
            timebaseDeclaration = run.environment.timebase.declaration
            measuresRealTime = run.environment.timebase.measuresRealTime
            result = run.result
            replayFingerprint = run.replayFingerprint.hex
            inputs = run.script.inputs
        }
    }

    struct RecordEntry: Encodable {
        let artifact: String
        let subject: String
        let check: String
        let path: ExecutionPath
        let result: RunResult

        init(path: String, record: EvidenceRecord) {
            artifact = path
            subject = record.subject
            check = record.check
            self.path = record.path
            result = record.result
        }
    }

    struct FileEntry: Encodable {
        let path: String
        let kind: String
        let tier: DataTier?
        let sha256: String
        let bytes: Int
    }

    struct ReviewEntry: Encodable {
        let path: String
        let kind: ExportArtifact.Kind
        let tier: DataTier
        let decision: String
        let reason: String?

        init(_ review: ArtifactReview) {
            path = review.path
            kind = review.kind
            tier = review.tier
            switch review.decision {
            case .approved:
                decision = "approved"
                reason = nil
            case .overridden(let text):
                decision = "overridden"
                reason = text
            case .refused(let text):
                decision = "refused"
                reason = text
            }
        }
    }
}

struct FailureEntry: Encodable {
    let source: String
    let step: String?
    let result: RunResult
    let detail: String
}
