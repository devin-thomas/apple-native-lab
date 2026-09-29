import Foundation
import LabDomain
import LabSupport

/// Why an export could not be previewed or written.
public enum EvidenceExportError: Error, Hashable, Sendable {
    public enum Stage: String, Hashable, Sendable {
        /// The destination folder the person chose.
        case destination
        /// Writing the files into the temporary folder.
        case writing
        /// Moving the finished folder into place.
        case finishing
    }

    case blankTitle
    /// Two selected artifacts would have the same export name, compared as the default file
    /// system compares names (case and Unicode normalization ignored), or one's folder is the
    /// other's file.
    case duplicatePath(String)
    /// A performance claim names a run that is not an approved artifact in this export.
    case claimWithoutRun(DemoRunID)
    /// The selection is larger than the export allows.
    case tooLarge(limit: Int)
    case invalidFolderName
    case confinement(Stage, ConfinementError)
    /// The written folder did not contain exactly the previewed files and bytes. Nothing was kept.
    case verificationFailed
}

/// Builds a reviewed, selected-artifact evidence export.
///
/// `preview(_:)` computes every file the export will contain, byte for byte, before anything is
/// written, and `EvidenceExportPreview.write(into:folderName:)` writes exactly those files and no
/// others. On the way:
///
/// 1. **Selection.** Only the artifacts in the request are considered. A file artifact names one
///    ordinary text file; folders are never exported, so nothing adjacent comes along.
/// 2. **Rights and privacy review.** A `public-fixture` artifact is approved. A `user-private` or
///    `unclassified` artifact is refused unless a `TierOverride` names its export path and tier;
///    the override's reason is recorded. A `sensitive` artifact is always refused.
/// 3. **Confinement.** File artifacts are read through the confined reader: no symbolic link, no
///    hidden component, no hard link, nothing outside the chosen root. A refusal names the
///    reason, never the source's path.
/// 4. **Content.** The export holds a manifest (`manifest.json`) and a summary (`summary.md`)
///    with the SHA-256 and size of every file, the build provenance, each run's adapter, store,
///    and timebase, every failure, the untested areas, and the performance claims, each linked to
///    its run. The summary's first line is the worst result among the exported runs and records.
public struct EvidenceExporter: Sendable {
    public static let format = "native-lab-evidence-export"
    public static let formatVersion = 1
    public static let maximumFileBytes = 4 << 20
    public static let maximumTotalBytes = 32 << 20

    private let now: @Sendable () -> Date
    private let diagnostics: DiagnosticsLog?

    /// - Parameter now: The wall clock for the export time. Inject a fixed one in tests.
    public init(now: @escaping @Sendable () -> Date = { Date() }, diagnostics: DiagnosticsLog? = nil) {
        self.now = now
        self.diagnostics = diagnostics
    }

    public func preview(_ request: EvidenceExportRequest) throws(EvidenceExportError) -> EvidenceExportPreview {
        do {
            let preview = try makePreview(request)
            diagnostics?.record(
                "evidence.export.preview",
                outcome: .succeeded,
                counts: ["files": preview.files.count, "refused": preview.reviews.filter(\.isRefused).count]
            )
            return preview
        } catch {
            diagnostics?.record("evidence.export.preview", outcome: .rejected, category: .invalidInput)
            throw error
        }
    }

    private func makePreview(_ request: EvidenceExportRequest) throws(EvidenceExportError) -> EvidenceExportPreview {
        guard !request.title.isBlank else { throw .blankTitle }
        var names = StagedPathSet()
        for reserved in ExportArtifact.reservedPaths.sorted() {
            _ = names.insert(try! StagedPath(reserved), isDirectory: false)
        }
        for artifact in request.artifacts where !names.insert(artifact.path, isDirectory: false) {
            throw .duplicatePath(artifact.path.value)
        }

        // Review and read every artifact. Refused artifacts contribute nothing but their review.
        var reviews: [ArtifactReview] = []
        var included: [(artifact: ExportArtifact, data: Data)] = []
        var total = 0
        for artifact in request.artifacts {
            let decision = review(artifact, overrides: request.overrides)
            if case .refused = decision {
                reviews.append(ArtifactReview(artifact, decision))
                continue
            }
            switch content(of: artifact) {
            case .success(let data):
                total += data.count
                guard total <= Self.maximumTotalBytes else { throw .tooLarge(limit: Self.maximumTotalBytes) }
                reviews.append(ArtifactReview(artifact, decision))
                included.append((artifact, data))
            case .failure(let refusal):
                reviews.append(ArtifactReview(artifact, .refused(reason: refusal.reason)))
            }
        }

        let runs: [(path: String, run: DemoRun)] = included.compactMap { entry in
            if case .run(let run) = entry.artifact.source { (entry.artifact.path.value, run) } else { nil }
        }
        let records: [(path: String, record: EvidenceRecord)] = included.compactMap { entry in
            if case .record(let record) = entry.artifact.source { (entry.artifact.path.value, record) } else { nil }
        }
        var claims: [ClaimEntry] = []
        for claim in request.claims {
            guard let match = runs.first(where: { $0.run.id == claim.runID }) else { throw .claimWithoutRun(claim.runID) }
            claims.append(ClaimEntry(claim, runArtifact: match.path))
        }

        let content = ExportContent(
            title: request.title.trimmingCharacters(in: .whitespacesAndNewlines),
            exportedAt: Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down)),
            provenance: request.provenance,
            runs: runs,
            records: records,
            reviews: reviews,
            claims: claims,
            requestUntested: request.untested
        )
        let artifactFiles = included
            .map { EvidenceExportPreview.File(path: $0.artifact.path, data: $0.data, kind: $0.artifact.kind.rawValue, tier: $0.artifact.tier) }
            .sorted { $0.path < $1.path }
        let summary = EvidenceExportPreview.File(
            path: try! StagedPath("summary.md"), data: Data(content.summaryText(files: artifactFiles).utf8), kind: "summary", tier: nil
        )
        let manifestText: String
        do {
            manifestText = try Canonical.text(content.manifest(files: [summary] + artifactFiles))
        } catch {
            throw .verificationFailed
        }
        let manifest = EvidenceExportPreview.File(
            path: try! StagedPath("manifest.json"), data: Data(manifestText.utf8), kind: "manifest", tier: nil
        )
        return EvidenceExportPreview(files: [summary, manifest] + artifactFiles, reviews: reviews, result: content.result)
    }

    // MARK: Review

    private func review(_ artifact: ExportArtifact, overrides: [TierOverride]) -> ArtifactReview.Decision {
        switch artifact.tier {
        case .publicFixture:
            return .approved
        case .sensitive:
            return .refused(reason: "Sensitive content is never exported, with or without an override.")
        case .userPrivate, .unclassified:
            if let override = overrides.first(where: { $0.path == artifact.path.value && $0.tier == artifact.tier }) {
                return .overridden(reason: override.reason)
            }
            return .refused(reason: "Only public-fixture content is exported without an explicit, recorded override; this artifact is \(artifact.tier.rawValue).")
        }
    }

    private struct Refusal: Error {
        let reason: String
    }

    private func content(of artifact: ExportArtifact) -> Result<Data, Refusal> {
        switch artifact.source {
        case .run(let run):
            guard let text = try? run.jsonText() else { return .failure(Refusal(reason: "The run could not be encoded.")) }
            return .success(Data(text.utf8))
        case .record(let record):
            guard let text = try? Canonical.text(record) else { return .failure(Refusal(reason: "The record could not be encoded.")) }
            return .success(Data(text.utf8))
        case .file(let root, let relative):
            let data: Data
            do {
                data = try ConfinedFile.read(relative, under: root, maximumBytes: Self.maximumFileBytes)
            } catch {
                return .failure(Refusal(reason: Self.explain(error)))
            }
            guard StrictUTF8.firstInvalidOffset(in: data) == nil else {
                return .failure(Refusal(reason: "The file is not UTF-8 text, so it could be media or a binary in disguise."))
            }
            return .success(data)
        }
    }

    static func explain(_ error: ConfinementError) -> String {
        switch error {
        case .invalidPath(let rejection): "The source name is not a safe relative path (\(rejection.rawValue))."
        case .rootUnavailable: "The source folder does not exist."
        case .missing: "The source file does not exist."
        case .hidden: "The source is hidden or inside a hidden folder; hidden files are never exported."
        case .symbolicLink: "A symbolic link is on the way to the source; links are never followed."
        case .notAFolder: "Part of the source path is not a folder."
        case .notARegularFile: "The source is a folder or a special file; only single ordinary files are exported."
        case .hardLinked: "The source has more than one hard link, so it may be another location's file."
        case .escapesRoot: "The source resolved outside its folder."
        case .tooLarge(let limit): "The source is larger than \(limit) bytes."
        case .changedWhileReading: "The source changed while it was read."
        case .alreadyExists: "Something already exists at the destination."
        case .system(let code): "The source could not be read (error \(code))."
        }
    }
}

/// The review outcome of one selected artifact.
public struct ArtifactReview: Hashable, Sendable {
    public enum Decision: Hashable, Sendable {
        /// `public-fixture`: exported.
        case approved
        /// Exported because the person recorded this reason.
        case overridden(reason: String)
        /// Not exported, for this reason.
        case refused(reason: String)
    }

    /// The export name the caller chose.
    public let path: String
    public let kind: ExportArtifact.Kind
    public let tier: DataTier
    public let decision: Decision

    init(_ artifact: ExportArtifact, _ decision: Decision) {
        path = artifact.path.value
        kind = artifact.kind
        tier = artifact.tier
        self.decision = decision
    }

    public var isRefused: Bool {
        if case .refused = decision { true } else { false }
    }

    var summary: String {
        switch decision {
        case .approved: "\(tier.rawValue), approved"
        case .overridden(let reason): "\(tier.rawValue), included by override: \(reason)"
        case .refused(let reason): "\(tier.rawValue), refused: \(reason)"
        }
    }
}

struct ClaimEntry: Encodable {
    let run: DemoRunID
    let runArtifact: String
    let script: DemoName
    let step: DemoStepID?
    let nanoseconds: Int64
    let timebase: Timebase
    let timebaseDeclaration: String
    let sampleCount: Int

    init(_ claim: PerformanceClaim, runArtifact: String) {
        run = claim.runID
        self.runArtifact = runArtifact
        script = claim.scriptID
        step = claim.step
        nanoseconds = claim.duration.nanoseconds
        timebase = claim.timebase
        timebaseDeclaration = claim.timebase.declaration
        sampleCount = claim.sampleCount
    }

    var sentence: String {
        let milliseconds = Double(nanoseconds) / 1_000_000
        let subject = step.map { "step `\($0)` of run \(run)" } ?? "all steps of run \(run)"
        return String(format: "%.3f ms", milliseconds)
            + ": \(subject) (`\(runArtifact)`), \(timebase.rawValue), \(sampleCount) sample."
    }
}
