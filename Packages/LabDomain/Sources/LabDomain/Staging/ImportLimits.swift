/// The resource limits one import must stay within.
///
/// The standard values are the protective defaults in docs/DATA_CONTRACTS.md ("Import resource
/// policy"); they are proposals, not measured device limits. A device or profile may impose
/// stricter limits, but never looser ones: every initializer clamps each value to the standard
/// maximum, and `narrowed(to:)` keeps the smaller of two values.
public struct ImportLimits: Hashable, Sendable {
    /// Files per import, including files expanded from an archive.
    public let maximumFiles: Int
    /// Shared text, and any JSON metadata file, in UTF-8 bytes.
    public let maximumTextBytes: Int
    /// All staged file content together, after expansion.
    public let maximumTotalBytes: Int
    /// Entries in an archive's directory, including folders, checked before anything expands.
    public let maximumArchiveEntries: Int
    /// Path components in a file name, and nesting levels in a JSON document.
    public let maximumNestingDepth: Int
    /// Expanded size divided by compressed size, for any archive entry larger than
    /// `compressionRatioFloorBytes`.
    public let maximumCompressionRatio: Int
    /// A shared link, in UTF-8 bytes. It must fit an item note.
    public let maximumLinkBytes: Int
    /// A shared page title, in UTF-8 bytes.
    public let maximumTitleBytes: Int
    /// A whole relative path, in UTF-8 bytes.
    public let maximumPathBytes: Int
    /// One path component, in UTF-8 bytes.
    public let maximumComponentBytes: Int

    /// Entries smaller than this are not checked for their compression ratio: tiny files can
    /// compress extremely well without being a threat.
    public static let compressionRatioFloorBytes = 1 << 20

    public static let standard = ImportLimits(
        unclampedFiles: 32,
        textBytes: 2 << 20,
        totalBytes: 1 << 30,
        archiveEntries: 2_000,
        nestingDepth: 16,
        compressionRatio: 100,
        linkBytes: 2_000,
        titleBytes: 1_024,
        pathBytes: 1_024,
        componentBytes: 255
    )

    /// Limits no looser than `standard`. Any value above the standard is clamped to it, and any
    /// value below 1 becomes 1.
    public init(
        maximumFiles: Int = ImportLimits.standard.maximumFiles,
        maximumTextBytes: Int = ImportLimits.standard.maximumTextBytes,
        maximumTotalBytes: Int = ImportLimits.standard.maximumTotalBytes,
        maximumArchiveEntries: Int = ImportLimits.standard.maximumArchiveEntries,
        maximumNestingDepth: Int = ImportLimits.standard.maximumNestingDepth,
        maximumCompressionRatio: Int = ImportLimits.standard.maximumCompressionRatio,
        maximumLinkBytes: Int = ImportLimits.standard.maximumLinkBytes,
        maximumTitleBytes: Int = ImportLimits.standard.maximumTitleBytes,
        maximumPathBytes: Int = ImportLimits.standard.maximumPathBytes,
        maximumComponentBytes: Int = ImportLimits.standard.maximumComponentBytes
    ) {
        let standard = ImportLimits.standard
        func clamp(_ value: Int, _ ceiling: Int) -> Int { min(max(value, 1), ceiling) }
        self.init(
            unclampedFiles: clamp(maximumFiles, standard.maximumFiles),
            textBytes: clamp(maximumTextBytes, standard.maximumTextBytes),
            totalBytes: clamp(maximumTotalBytes, standard.maximumTotalBytes),
            archiveEntries: clamp(maximumArchiveEntries, standard.maximumArchiveEntries),
            nestingDepth: clamp(maximumNestingDepth, standard.maximumNestingDepth),
            compressionRatio: clamp(maximumCompressionRatio, standard.maximumCompressionRatio),
            linkBytes: clamp(maximumLinkBytes, standard.maximumLinkBytes),
            titleBytes: clamp(maximumTitleBytes, standard.maximumTitleBytes),
            pathBytes: clamp(maximumPathBytes, standard.maximumPathBytes),
            componentBytes: clamp(maximumComponentBytes, standard.maximumComponentBytes)
        )
    }

    private init(
        unclampedFiles files: Int,
        textBytes: Int,
        totalBytes: Int,
        archiveEntries: Int,
        nestingDepth: Int,
        compressionRatio: Int,
        linkBytes: Int,
        titleBytes: Int,
        pathBytes: Int,
        componentBytes: Int
    ) {
        maximumFiles = files
        maximumTextBytes = textBytes
        maximumTotalBytes = totalBytes
        maximumArchiveEntries = archiveEntries
        maximumNestingDepth = nestingDepth
        maximumCompressionRatio = compressionRatio
        maximumLinkBytes = linkBytes
        maximumTitleBytes = titleBytes
        maximumPathBytes = pathBytes
        maximumComponentBytes = componentBytes
    }

    /// The stricter of the two values for every limit.
    public func narrowed(to other: ImportLimits) -> ImportLimits {
        ImportLimits(
            unclampedFiles: min(maximumFiles, other.maximumFiles),
            textBytes: min(maximumTextBytes, other.maximumTextBytes),
            totalBytes: min(maximumTotalBytes, other.maximumTotalBytes),
            archiveEntries: min(maximumArchiveEntries, other.maximumArchiveEntries),
            nestingDepth: min(maximumNestingDepth, other.maximumNestingDepth),
            compressionRatio: min(maximumCompressionRatio, other.maximumCompressionRatio),
            linkBytes: min(maximumLinkBytes, other.maximumLinkBytes),
            titleBytes: min(maximumTitleBytes, other.maximumTitleBytes),
            pathBytes: min(maximumPathBytes, other.maximumPathBytes),
            componentBytes: min(maximumComponentBytes, other.maximumComponentBytes)
        )
    }

    /// The largest staging record this build reads: the text limit with room for JSON escaping
    /// of line breaks and quotes, plus the file list.
    public var maximumRecordBytes: Int { 2 * maximumTextBytes + 64 * 1_024 + maximumFiles * (maximumPathBytes * 2 + 160) }
}
