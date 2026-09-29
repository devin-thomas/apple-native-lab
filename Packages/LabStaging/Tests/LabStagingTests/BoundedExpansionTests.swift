import Foundation
import LabDomain
@testable import LabStaging
import Testing

// The inflater and the file writer are internal, so this file imports LabStaging @testable.

/// CORE-006: two independent bounds stop a lying archive entry. The inflater stops at the size
/// the entry declared, and the staged-file writer refuses bytes beyond its budget. Each is tested
/// alone here, because in `ArchiveTests` either one hides the other.
@Suite struct BoundedExpansionTests {
    @Test func theInflaterStopsAtItsLimitBeforeHandingOnAnyExcess() throws {
        let compressed = ZipBuilder.deflate(Data(count: 32 << 20))
        var offset = 0
        var delivered = 0
        #expect(throws: ImportRejection.expandsBeyondDeclaredSize(file: 7)) {
            _ = try BoundedInflater.inflate(
                compressedSize: compressed.count,
                outputLimit: 100_000,
                entry: 7,
                read: { count throws(ImportRejection) in
                    let chunk = compressed.subdata(in: offset..<min(offset + count, compressed.count))
                    offset += chunk.count
                    return chunk
                },
                sink: { data throws(ImportRejection) in delivered += data.count }
            )
        }
        #expect(delivered <= 100_000, "no byte beyond the limit reached the sink")
    }

    @Test func theZipReaderBoundsEachEntryByItsDeclaredSize() throws {
        let directory = try TemporaryDirectory()
        var liar = ZipBuilder.Entry("small.txt", Data(count: 32 << 20))
        liar.declaredSize = 1_000
        let url = try directory.file("liar.zip", ZipBuilder([liar]).build())
        let handle = try FileHandle(forReadingFrom: url)
        let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int)
        var reader = try ZipReader(handle: handle, size: size, limits: .standard)
        try reader.verifyLayout()
        var delivered = 0
        #expect(throws: ImportRejection.expandsBeyondDeclaredSize(file: 1)) {
            try reader.extract(reader.entries[0], position: 1) { data throws(ImportRejection) in delivered += data.count }
        }
        #expect(delivered <= 1_000)
    }

    @Test func theInflaterExpandsAnHonestStreamExactly() throws {
        let original = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 / 7) })
        let compressed = ZipBuilder.deflate(original)
        var offset = 0
        var output = Data()
        let produced = try BoundedInflater.inflate(
            compressedSize: compressed.count, outputLimit: original.count, entry: 1,
            read: { count throws(ImportRejection) in
                let chunk = compressed.subdata(in: offset..<min(offset + count, compressed.count))
                offset += chunk.count
                return chunk
            },
            sink: { data throws(ImportRejection) in output.append(data) }
        )
        #expect(produced == original.count && output == original)
    }

    @Test func theWriterRefusesBytesBeyondItsBudget() throws {
        let directory = try TemporaryDirectory()
        var writer = try StagedFileWriter(
            url: directory.url.appending(path: "0"), path: try StagedPath("a.bin"), position: 3, limits: .standard,
            budget: 10, checkNestedArchive: false
        )
        try writer.append(Data(count: 10), overflow: .expandsBeyondDeclaredSize(file: 3))
        #expect(throws: ImportRejection.expandsBeyondDeclaredSize(file: 3)) {
            try writer.append(Data(count: 1), overflow: .expandsBeyondDeclaredSize(file: 3))
        }
        #expect(try Data(contentsOf: directory.url.appending(path: "0")).count == 10, "the excess byte was never written")
    }
}
