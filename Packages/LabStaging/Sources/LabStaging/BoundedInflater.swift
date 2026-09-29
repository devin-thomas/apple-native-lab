import Compression
import Foundation
import LabDomain

/// The CRC-32 a ZIP entry records for its expanded content (ISO 3309, reflected 0xEDB88320).
struct CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    private(set) var value: UInt32 = 0

    mutating func update(_ bytes: some Sequence<UInt8>) {
        var crc = ~value
        for byte in bytes { crc = Self.table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        value = ~crc
    }
}

/// Expands raw DEFLATE data (a ZIP entry's method 8) while enforcing an output limit.
///
/// The limit is the size the entry declared. The check runs on every 64 KiB of output, before
/// that output is written anywhere, so an entry that lies about its size stops at the limit
/// instead of filling the disk: the decompressed-size limit applies while streaming, not only
/// to the archive's headers (docs/DATA_CONTRACTS.md). Cancellation is checked between chunks.
enum BoundedInflater {
    static let chunkSize = 64 * 1_024

    /// - Parameters:
    ///   - read: Returns up to the requested number of compressed bytes, or none at the end.
    ///   - entry: The entry's 1-based position, for the rejection.
    ///   - sink: Receives each piece of expanded output, in order.
    /// - Returns: The number of bytes produced.
    static func inflate(
        compressedSize: Int,
        outputLimit: Int,
        entry: Int,
        read: (Int) throws(ImportRejection) -> Data,
        sink: (Data) throws(ImportRejection) -> Void
    ) throws(ImportRejection) -> Int {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw .corruptArchive
        }
        defer { compression_stream_destroy(stream) }
        let output = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { output.deallocate() }

        var remaining = compressedSize
        var chunk = Data()
        var offset = 0
        var produced = 0
        while true {
            guard !Task.isCancelled else { throw .cancelled }
            if offset == chunk.count, remaining > 0 {
                chunk = try read(min(chunkSize, remaining))
                guard !chunk.isEmpty else { throw .corruptArchive }
                remaining -= chunk.count
                offset = 0
            }
            let finalize = remaining == 0
            let consumedBefore = offset
            let status: compression_status = chunk.withUnsafeBytes { raw in
                let source = raw.bindMemory(to: UInt8.self)
                if let base = source.baseAddress {
                    stream.pointee.src_ptr = base + offset
                    stream.pointee.src_size = source.count - offset
                } else {
                    stream.pointee.src_ptr = UnsafePointer(output)
                    stream.pointee.src_size = 0
                }
                stream.pointee.dst_ptr = output
                stream.pointee.dst_size = chunkSize
                let status = compression_stream_process(stream, finalize ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                offset = chunk.count - stream.pointee.src_size
                return status
            }
            let count = chunkSize - stream.pointee.dst_size
            if count > 0 {
                produced += count
                guard produced <= outputLimit else { throw .expandsBeyondDeclaredSize(file: entry) }
                try sink(Data(bytes: output, count: count))
            }
            switch status {
            case COMPRESSION_STATUS_END:
                // Anything after the end of the DEFLATE stream is not part of this entry.
                guard offset == chunk.count, remaining == 0 else { throw .corruptArchive }
                return produced
            case COMPRESSION_STATUS_OK:
                // All input given and nothing more produced: the stream is truncated.
                if finalize, offset == chunk.count, count == 0, consumedBefore == offset { throw .corruptArchive }
            default:
                throw .corruptArchive
            }
        }
    }
}
