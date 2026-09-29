import Foundation
import LabDomain
import LabSupport

/// Why a selection could not be made. Paths here are the export names the caller chose, never a
/// source file's name.
public enum ExportSelectionError: Error, Hashable, Sendable {
    case invalidPath(PathRejection)
    /// A component of the export name starts with `.`. Hidden files are never exported.
    case hiddenPath
    /// `summary.md` and `manifest.json` at the top level are written by the exporter itself.
    case reservedPath
    /// The file type is not on the export allowlist.
    case unsupportedFileType(String)
    /// The export name's extension differs from the source's.
    case extensionMismatch
    /// An override's reason is blank.
    case blankReason
    /// The tier cannot be overridden: sensitive content is never exported.
    case overrideNotAllowed(DataTier)
}

/// One thing a person selected for an evidence export, with the export name it will have and the
/// rights tier it declares.
public struct ExportArtifact: Sendable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case demoRun = "demo-run"
        case evidenceRecord = "evidence-record"
        case file
    }

    enum Source: Sendable {
        case run(DemoRun)
        case record(EvidenceRecord)
        case file(root: URL, relative: StagedPath)
    }

    /// Text formats a file artifact may have. The bytes must also be strict UTF-8, so media or a
    /// binary cannot pass as text. Images, audio, video, and archives are refused: they can carry
    /// embedded location, device, and author metadata that this exporter does not strip.
    public static let allowedFileExtensions: Set<String> = ["json", "md", "txt", "csv"]
    static let reservedPaths: Set<String> = ["summary.md", "manifest.json"]

    /// Where the artifact goes inside the export.
    public let path: StagedPath
    public let kind: Kind
    public let tier: DataTier
    let source: Source

    private init(path: StagedPath, kind: Kind, tier: DataTier, source: Source) {
        self.path = path
        self.kind = kind
        self.tier = tier
        self.source = source
    }

    /// A demo run, written as its JSON record. Its tier is the script's tier.
    ///
    /// - Parameter path: The export name, `runs/<script>-<run ID>.json` by default.
    public static func run(_ run: DemoRun, at path: String? = nil) throws(ExportSelectionError) -> ExportArtifact {
        let exportPath = try validated(path ?? "runs/\(run.script.id)-\(run.id.rawValue.uuidString.lowercased()).json", extension: "json")
        return ExportArtifact(path: exportPath, kind: .demoRun, tier: run.script.dataTier, source: .run(run))
    }

    /// An evidence record, written as its JSON. The caller declares its tier.
    public static func record(_ record: EvidenceRecord, at path: String, tier: DataTier) throws(ExportSelectionError) -> ExportArtifact {
        ExportArtifact(path: try validated(path, extension: "json"), kind: .evidenceRecord, tier: tier, source: .record(record))
    }

    /// One ordinary text file below `root`, exported under a name the caller chooses so the
    /// source's own name never appears in the export.
    ///
    /// The file is read when the preview is made, through the confined reader: `relativePath`
    /// must pass the import path policy, no component may be hidden or a symbolic link, and the
    /// file must be an ordinary, singly linked file inside `root`. A folder is never exported.
    public static func file(
        _ relativePath: String,
        in root: URL,
        tier: DataTier,
        at path: String
    ) throws(ExportSelectionError) -> ExportArtifact {
        let relative: StagedPath
        do { relative = try StagedPath(relativePath) } catch { throw .invalidPath(error) }
        let sourceExtension = relative.pathExtension
        guard allowedFileExtensions.contains(sourceExtension) else { throw .unsupportedFileType(sourceExtension) }
        let exportPath = try validated(path, extension: sourceExtension)
        return ExportArtifact(path: exportPath, kind: .file, tier: tier, source: .file(root: root, relative: relative))
    }

    private static func validated(_ raw: String, extension required: String) throws(ExportSelectionError) -> StagedPath {
        let path: StagedPath
        do { path = try StagedPath(raw) } catch { throw .invalidPath(error) }
        guard !path.components.contains(where: { $0.hasPrefix(".") }) else { throw .hiddenPath }
        guard !reservedPaths.contains(path.value.lowercased()) else { throw .reservedPath }
        guard path.pathExtension == required else {
            throw allowedFileExtensions.contains(path.pathExtension) || path.pathExtension.isEmpty
                ? .extensionMismatch : .unsupportedFileType(path.pathExtension)
        }
        return path
    }
}

/// A person's explicit decision to export an artifact whose tier is not `public-fixture`.
///
/// It names the export path and the tier it accepts, so it covers only that artifact at that
/// tier, and its reason is written into the export's manifest and summary.
public struct TierOverride: Hashable, Sendable {
    public let path: String
    public let tier: DataTier
    public let reason: String

    public init(path: String, tier: DataTier, reason: String) throws(ExportSelectionError) {
        guard tier.allowsOverride else { throw .overrideNotAllowed(tier) }
        guard !reason.isBlank else { throw .blankReason }
        let validated: StagedPath
        do { validated = try StagedPath(path) } catch { throw .invalidPath(error) }
        self.path = validated.value
        self.tier = tier
        self.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Everything a person chose for one export.
public struct EvidenceExportRequest: Sendable {
    public var title: String
    public var artifacts: [ExportArtifact]
    public var overrides: [TierOverride]
    /// Durations to publish. Each must come from a run selected in `artifacts`.
    public var claims: [PerformanceClaim]
    /// Areas the exported evidence does not cover, beyond those the runs and records state.
    public var untested: [String]
    /// The build that produced the evidence.
    public var provenance: BuildProvenance

    public init(
        title: String,
        artifacts: [ExportArtifact],
        overrides: [TierOverride] = [],
        claims: [PerformanceClaim] = [],
        untested: [String] = [],
        provenance: BuildProvenance
    ) {
        self.title = title
        self.artifacts = artifacts
        self.overrides = overrides
        self.claims = claims
        self.untested = untested
        self.provenance = provenance
    }
}
