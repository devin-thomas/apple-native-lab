/// One entry from an archive's directory, as a format reader reports it, before anything expands.
public struct ArchiveEntry: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case file
        case directory
        /// A symbolic or hard link.
        case link
        /// A device, pipe, socket, or anything else.
        case other
    }

    public let nameBytes: [UInt8]
    public let kind: Kind
    public let compressedSize: Int
    /// The expanded size the archive claims. Extraction still enforces it while streaming,
    /// because a hostile archive can lie.
    public let declaredSize: Int
    public let isEncrypted: Bool

    public init(nameBytes: [UInt8], kind: Kind, compressedSize: Int, declaredSize: Int, isEncrypted: Bool) {
        self.nameBytes = nameBytes
        self.kind = kind
        self.compressedSize = compressedSize
        self.declaredSize = declaredSize
        self.isEncrypted = isEncrypted
    }
}

/// The files an archive may expand to, once its directory has passed `ArchivePolicy`.
public struct ArchivePlan: Hashable, Sendable {
    public struct File: Hashable, Sendable {
        /// The entry's position in the archive's directory, from 0.
        public let entryIndex: Int
        public let path: StagedPath
        public let declaredSize: Int
    }

    public let files: [File]
    public var totalDeclaredSize: Int { files.reduce(0) { $0 + $1.declaredSize } }
}

/// Decides, from an archive's directory alone, whether it may be expanded into staging.
///
/// This is format-neutral: a reader (for example the ZIP reader in `LabStaging`) lists the
/// entries, and this policy refuses, in order: too many entries; encrypted, link, or special
/// entries; unsafe names (`StagedPath`); a name that is itself an archive; names that collide;
/// declared sizes beyond the limits; a compression ratio that marks a zip bomb; and more files
/// than one import may hold. Passing is necessary, not sufficient: extraction must still enforce
/// each declared size while streaming and sniff every file for a nested archive.
public enum ArchivePolicy {
    /// Extensions of archive and compressed container formats that are never expanded inside
    /// another archive.
    public static let nestedArchiveExtensions: Set<String> = [
        "zip", "anlabpack", "jar", "gz", "tgz", "tar", "bz2", "tbz", "xz", "txz", "7z", "rar", "zst", "lz",
        "lzma", "z", "cpio", "aar", "xar", "pkg", "dmg", "iso", "ipa", "apk",
    ]

    public static func plan(_ entries: [ArchiveEntry], limits: ImportLimits) throws(ImportRejection) -> ArchivePlan {
        guard entries.count <= limits.maximumArchiveEntries else { throw .tooManyEntries(limit: limits.maximumArchiveEntries) }
        var names = StagedPathSet()
        var files: [ArchivePlan.File] = []
        var total = 0
        var compressedTotal = 0
        for (index, entry) in entries.enumerated() {
            let position = index + 1
            if entry.isEncrypted { throw .unsupportedArchive(.encryption) }
            switch entry.kind {
            case .link: throw .linkEntry(file: position)
            case .other: throw .unsupportedEntryType(file: position)
            case .file, .directory: break
            }
            let isDirectory = entry.kind == .directory
            let path: StagedPath
            do {
                path = try StagedPath(bytes: entry.nameBytes, isDirectory: isDirectory, limits: limits)
            } catch {
                throw .unsafePath(file: position, error)
            }
            if !isDirectory, nestedArchiveExtensions.contains(path.pathExtension) { throw .nestedArchive(file: position) }
            guard names.insert(path, isDirectory: isDirectory) else { throw .duplicatePath(file: position) }
            guard !isDirectory else { continue }
            guard entry.declaredSize >= 0, entry.compressedSize >= 0 else { throw .corruptArchive }
            guard entry.declaredSize <= limits.maximumTotalBytes - total else {
                throw .expandedSizeTooLarge(limit: limits.maximumTotalBytes)
            }
            if exceedsRatio(declared: entry.declaredSize, compressed: entry.compressedSize, limits: limits) {
                throw .compressionRatioTooHigh(file: position, limit: limits.maximumCompressionRatio)
            }
            total += entry.declaredSize
            compressedTotal += entry.compressedSize
            files.append(ArchivePlan.File(entryIndex: index, path: path, declaredSize: entry.declaredSize))
        }
        // Many small entries can each stay under the ratio floor while the whole archive is a bomb.
        if exceedsRatio(declared: total, compressed: compressedTotal, limits: limits) {
            throw .archiveRatioTooHigh(limit: limits.maximumCompressionRatio)
        }
        guard files.count <= limits.maximumFiles else { throw .tooManyFiles(limit: limits.maximumFiles) }
        return ArchivePlan(files: files)
    }

    /// Whether leading bytes are the signature of an archive or compressed container: ZIP, gzip,
    /// bzip2, xz, zstd, 7z, RAR, Apple Archive, xar, or a POSIX tar header.
    public static func looksLikeArchive(_ prefix: some Collection<UInt8>) -> Bool {
        let bytes = Array(prefix.prefix(512))
        let signatures: [[UInt8]] = [
            [0x50, 0x4B, 0x03, 0x04], [0x50, 0x4B, 0x05, 0x06], [0x50, 0x4B, 0x07, 0x08],
            [0x1F, 0x8B], [0x42, 0x5A, 0x68], [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00], [0x28, 0xB5, 0x2F, 0xFD],
            [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07],
            Array("AA01".utf8), Array("xar!".utf8),
        ]
        if signatures.contains(where: { bytes.starts(with: $0) }) { return true }
        return bytes.count >= 262 && Array(bytes[257..<262]) == Array("ustar".utf8)
    }

    private static func exceedsRatio(declared: Int, compressed: Int, limits: ImportLimits) -> Bool {
        guard declared > ImportLimits.compressionRatioFloorBytes else { return false }
        return compressed == 0 || declared / compressed > limits.maximumCompressionRatio
    }
}
