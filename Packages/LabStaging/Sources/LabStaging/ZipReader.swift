import Foundation
import LabDomain

/// One entry in a ZIP archive's central directory.
struct ZipEntry {
    let descriptor: ArchiveEntry
    let method: UInt16
    let flags: UInt16
    let crc32: UInt32
    let localHeaderOffset: Int
    /// Where the entry's compressed bytes start, known after `ZipReader.verifyLayout()`.
    var dataOffset = 0
}

/// Reads a ZIP archive's structure strictly and expands entries with bounded output.
///
/// It accepts the plain 32-bit format with stored or deflated entries, and refuses, before
/// anything expands: a missing or ambiguous end record, ZIP64, multiple disks, encryption, other
/// compression methods, more entries than the limit, bytes before the first entry or between
/// entries beyond a data descriptor, local headers that disagree with the directory, and entries
/// whose byte ranges overlap (the "overlapping files" zip bomb). Directory and archive sizes are
/// bounded before they are read into memory.
struct ZipReader {
    static let endRecordSize = 22
    static let maximumCommentLength = 0xFFFF
    static let maximumDirectoryBytes = 64 << 20

    private let handle: FileHandle
    private let size: Int
    private(set) var entries: [ZipEntry] = []
    private let directoryOffset: Int

    init(handle: FileHandle, size: Int, limits: ImportLimits) throws(ImportRejection) {
        self.handle = handle
        self.size = size
        guard size >= Self.endRecordSize else { throw .notAnArchive }

        // The end record is the last 22 bytes plus a comment of up to 65,535 bytes. Accept only a
        // signature whose comment length reaches exactly to the end of the file.
        let tailLength = min(size, Self.endRecordSize + Self.maximumCommentLength)
        let tail = try Self.read(handle, at: size - tailLength, count: tailLength)
        var endOffset: Int?
        var position = tail.count - Self.endRecordSize
        while position >= 0 {
            if tail.uint32(at: position) == 0x0605_4B50,
               position + Self.endRecordSize + Int(tail.uint16(at: position + 20)) == tail.count {
                endOffset = position
                break
            }
            position -= 1
        }
        guard let endInTail = endOffset else { throw .notAnArchive }
        let end = size - tailLength + endInTail
        if endInTail >= 20, tail.uint32(at: endInTail - 20) == 0x0706_4B50 { throw .unsupportedArchive(.zip64) }

        let disk = tail.uint16(at: endInTail + 4)
        let directoryDisk = tail.uint16(at: endInTail + 6)
        let entriesOnDisk = tail.uint16(at: endInTail + 8)
        let totalEntries = tail.uint16(at: endInTail + 10)
        let directorySize = tail.uint32(at: endInTail + 12)
        let offset = tail.uint32(at: endInTail + 16)
        if totalEntries == 0xFFFF || directorySize == 0xFFFF_FFFF || offset == 0xFFFF_FFFF { throw .unsupportedArchive(.zip64) }
        guard disk == 0, directoryDisk == 0, entriesOnDisk == totalEntries else { throw .unsupportedArchive(.multipleDisks) }
        guard Int(totalEntries) <= limits.maximumArchiveEntries else { throw .tooManyEntries(limit: limits.maximumArchiveEntries) }
        guard Int(directorySize) <= Self.maximumDirectoryBytes, Int(offset) + Int(directorySize) <= end else { throw .corruptArchive }
        guard Int(offset) + Int(directorySize) == end else { throw .unsupportedArchive(.extraData) }
        directoryOffset = Int(offset)

        let directory = try Self.read(handle, at: Int(offset), count: Int(directorySize))
        var cursor = 0
        for _ in 0..<Int(totalEntries) {
            guard cursor + 46 <= directory.count, directory.uint32(at: cursor) == 0x0201_4B50 else { throw .corruptArchive }
            let madeBy = directory.uint16(at: cursor + 4)
            let flags = directory.uint16(at: cursor + 8)
            let method = directory.uint16(at: cursor + 10)
            let crc = directory.uint32(at: cursor + 16)
            let compressed = directory.uint32(at: cursor + 20)
            let expanded = directory.uint32(at: cursor + 24)
            let nameLength = Int(directory.uint16(at: cursor + 28))
            let extraLength = Int(directory.uint16(at: cursor + 30))
            let commentLength = Int(directory.uint16(at: cursor + 32))
            let startDisk = directory.uint16(at: cursor + 34)
            let external = directory.uint32(at: cursor + 38)
            let localOffset = directory.uint32(at: cursor + 42)
            let next = cursor + 46 + nameLength + extraLength + commentLength
            guard next <= directory.count else { throw .corruptArchive }
            if compressed == 0xFFFF_FFFF || expanded == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF || startDisk == 0xFFFF {
                throw .unsupportedArchive(.zip64)
            }
            guard startDisk == 0 else { throw .unsupportedArchive(.multipleDisks) }
            let name = Array(directory[(directory.startIndex + cursor + 46)..<(directory.startIndex + cursor + 46 + nameLength)])
            let kind = Self.kind(name: name, madeBy: madeBy, external: external)
            let encrypted = flags & 0x0001 != 0 || flags & 0x0040 != 0 || method == 99
            if kind == .file, !encrypted, method != 0, method != 8 { throw .unsupportedArchive(.compressionMethod) }
            if kind == .directory, compressed != 0 || expanded != 0 { throw .corruptArchive }
            entries.append(ZipEntry(
                descriptor: ArchiveEntry(
                    nameBytes: name, kind: kind, compressedSize: Int(compressed), declaredSize: Int(expanded), isEncrypted: encrypted
                ),
                method: method, flags: flags, crc32: crc, localHeaderOffset: Int(localOffset)
            ))
            cursor = next
        }
        guard cursor == directory.count else { throw .corruptArchive }
    }

    /// Reads every local header and checks that it matches the directory, that entries start
    /// at the beginning of the file, and that no two entries share bytes.
    mutating func verifyLayout() throws(ImportRejection) {
        for index in entries.indices {
            let entry = entries[index]
            let header = try Self.read(handle, at: entry.localHeaderOffset, count: 30)
            guard header.uint32(at: 0) == 0x0403_4B50 else { throw .corruptArchive }
            let flags = header.uint16(at: 6)
            let method = header.uint16(at: 8)
            let nameLength = Int(header.uint16(at: 26))
            let extraLength = Int(header.uint16(at: 28))
            guard method == entry.method, flags & 0x0041 == entry.flags & 0x0041 else { throw .corruptArchive }
            let name = try Self.read(handle, at: entry.localHeaderOffset + 30, count: nameLength)
            guard Array(name) == entry.descriptor.nameBytes else { throw .corruptArchive }
            entries[index].dataOffset = entry.localHeaderOffset + 30 + nameLength + extraLength
            guard entries[index].dataOffset + entry.descriptor.compressedSize <= directoryOffset else { throw .corruptArchive }
        }
        // Sorted by position, each entry must end before the next begins. A data descriptor
        // (at most 16 bytes) may sit between them; anything more is unaccounted data.
        let ordered = entries.sorted { $0.localHeaderOffset < $1.localHeaderOffset }
        var end = 0
        var slack = 0
        for entry in ordered {
            if entry.localHeaderOffset < end { throw .overlappingEntries }
            if entry.localHeaderOffset > end + slack { throw .unsupportedArchive(.extraData) }
            end = entry.dataOffset + entry.descriptor.compressedSize
            slack = entry.flags & 0x0008 != 0 ? 16 : 0
        }
        if directoryOffset > end + slack { throw .unsupportedArchive(.extraData) }
    }

    /// Expands one entry into `sink`, producing at most `declaredSize` bytes, and checks its CRC.
    /// - Parameter position: The entry's 1-based position, for rejections.
    func extract(_ entry: ZipEntry, position: Int, sink: (Data) throws(ImportRejection) -> Void) throws(ImportRejection) {
        var offset = entry.dataOffset
        func read(_ count: Int) throws(ImportRejection) -> Data {
            let data = try Self.read(handle, at: offset, count: count)
            offset += data.count
            return data
        }
        var crc = CRC32()
        func checked(_ data: Data) throws(ImportRejection) {
            crc.update(data)
            try sink(data)
        }
        let produced: Int
        switch entry.method {
        case 0:
            guard entry.descriptor.compressedSize <= entry.descriptor.declaredSize else {
                throw .expandsBeyondDeclaredSize(file: position)
            }
            var remaining = entry.descriptor.compressedSize
            while remaining > 0 {
                guard !Task.isCancelled else { throw .cancelled }
                let data = try read(min(BoundedInflater.chunkSize, remaining))
                remaining -= data.count
                try checked(data)
            }
            produced = entry.descriptor.compressedSize
        case 8:
            produced = try BoundedInflater.inflate(
                compressedSize: entry.descriptor.compressedSize,
                outputLimit: entry.descriptor.declaredSize,
                entry: position,
                read: read,
                sink: checked
            )
        default:
            throw .unsupportedArchive(.compressionMethod)
        }
        guard produced == entry.descriptor.declaredSize else { throw .corruptArchive }
        guard crc.value == entry.crc32 else { throw .checksumMismatch(file: position) }
    }

    // MARK: Helpers

    private static func kind(name: [UInt8], madeBy: UInt16, external: UInt32) -> ArchiveEntry.Kind {
        let endsWithSlash = name.last == UInt8(ascii: "/")
        let host = madeBy >> 8
        let mode = external >> 16
        if host == 3 || host == 19, mode != 0 {
            switch mode & 0o170000 {
            case 0o120000: return .link
            case 0o040000: return .directory
            case 0o100000: return endsWithSlash ? .other : .file
            default: return .other
            }
        }
        return endsWithSlash || external & 0x10 != 0 ? .directory : .file
    }

    private static func read(_ handle: FileHandle, at offset: Int, count: Int) throws(ImportRejection) -> Data {
        guard offset >= 0, count >= 0 else { throw .corruptArchive }
        guard count > 0 else { return Data() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.read(upToCount: count), data.count == count else { throw ImportRejection.corruptArchive }
            return data
        } catch {
            throw .corruptArchive
        }
    }
}

extension Data {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(uint16(at: offset)) | UInt32(uint16(at: offset + 2)) << 16
    }
}
