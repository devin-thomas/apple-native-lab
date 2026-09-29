import Foundation
import LabDomain
import LabStaging
import Testing

/// CORE-006 acceptance: a path traversal or archive expansion attempt is rejected before
/// adoption. Every archive here is built by the test; none is committed.
@Suite struct ArchiveTests {
    private func stage(_ archive: Data, limits: ImportLimits = .standard) async throws -> (StagingFixture, Result<StagingOutcome, ImportRejection>) {
        let staging = try StagingFixture(limits: limits)
        let url = try staging.directory.file("shared.zip", archive)
        let area = staging.area
        do {
            return (staging, .success(try await area.stageArchive(at: url)))
        } catch {
            return (staging, .failure(error))
        }
    }

    /// Stages `archive`, expects `expected`, and checks nothing was left behind.
    private func expectRefused(
        _ archive: Data,
        _ expected: ImportRejection,
        limits: ImportLimits = .standard,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let (staging, result) = try await stage(archive, limits: limits)
        guard case .failure(let rejection) = result else {
            Issue.record("the archive was staged", sourceLocation: sourceLocation)
            return
        }
        #expect(rejection == expected, sourceLocation: sourceLocation)
        expectReadable(rejection, sourceLocation: sourceLocation)
        await staging.expectNothingStaged(sourceLocation: sourceLocation)
        #expect(staging.diagnostics.events.last?.category == expected.category, sourceLocation: sourceLocation)
    }

    @Test func anOrdinaryArchiveExpandsIntoStaging() async throws {
        let text = Data(String(repeating: "A line of notes.\n", count: 400).utf8)
        let archive = ZipBuilder([
            .directory("notes/"),
            ZipBuilder.Entry("notes/today.txt", text),
            ZipBuilder.Entry("manifest.anlab", Data("{\"schemaVersion\":1}".utf8), method: 0),
            ZipBuilder.Entry("empty.txt", Data(), method: 0),
        ]).build()
        let (staging, result) = try await stage(archive)
        let outcome = try result.get()
        let record = try await staging.area.validatedRecord(outcome.id)
        guard case .files(let files) = record.payload else {
            Issue.record("expected files")
            return
        }
        #expect(files.map(\.path.value) == ["notes/today.txt", "manifest.anlab", "empty.txt"])
        #expect(files.map(\.byteCount) == [text.count, 19, 0])
        #expect(try await staging.area.contents(of: 0, in: outcome.id) == text)
        #expect(staging.entries("incoming").isEmpty)
    }

    @Test(arguments: try HostileFixtures.nameCases())
    func aTraversalNameInsideAnArchiveIsRefused(_ hostile: HostileFixtures.NameCase) async throws {
        let archive = ZipBuilder([
            ZipBuilder.Entry("fine.txt", Data("fine".utf8), method: 0),
            ZipBuilder.Entry(nameBytes: hostile.bytes, Data("escaped".utf8)),
        ]).build()
        try await expectRefused(archive, .unsafePath(file: 2, hostile.expected))
    }

    @Test func linkAndSpecialEntriesAreRefused() async throws {
        try await expectRefused(
            ZipBuilder([ZipBuilder.Entry("a.txt", Data("a".utf8)), .symbolicLink("link", to: "../../../../etc/hosts")]).build(),
            .linkEntry(file: 2)
        )
        var fifo = ZipBuilder.Entry("pipe", method: 0)
        fifo.externalAttributes = 0o010644 << 16
        try await expectRefused(ZipBuilder([fifo]).build(), .unsupportedEntryType(file: 1))
    }

    @Test func unsupportedArchiveFeaturesAreRefused() async throws {
        var encrypted = ZipBuilder.Entry("secret.txt", Data("x".utf8), method: 0)
        encrypted.flags |= 0x0001
        try await expectRefused(ZipBuilder([encrypted]).build(), .unsupportedArchive(.encryption))

        var zip64 = ZipBuilder([ZipBuilder.Entry("a.txt", Data("a".utf8))])
        zip64.zip64Locator = true
        try await expectRefused(zip64.build(), .unsupportedArchive(.zip64))

        var split = ZipBuilder([ZipBuilder.Entry("a.txt", Data("a".utf8))])
        split.diskNumber = 1
        try await expectRefused(split.build(), .unsupportedArchive(.multipleDisks))

        try await expectRefused(ZipBuilder([ZipBuilder.Entry("a.txt", Data("a".utf8), method: 12)]).build(), .unsupportedArchive(.compressionMethod))

        var prefixed = ZipBuilder([ZipBuilder.Entry("a.txt", Data("a".utf8))])
        prefixed.prefix = Data("#!/bin/sh\nexit 0\n".utf8)
        try await expectRefused(prefixed.build(), .unsupportedArchive(.extraData))
    }

    @Test func tooManyEntriesAreRefusedBeforeTheDirectoryIsRead() async throws {
        let entries = (0...2_000).map { ZipBuilder.Entry("f\($0).txt", method: 0) }
        try await expectRefused(ZipBuilder(entries).build(), .tooManyEntries(limit: 2_000))
        try await expectRefused(ZipBuilder((0..<33).map { ZipBuilder.Entry("f\($0).txt", method: 0) }).build(), .tooManyFiles(limit: 32))
    }

    @Test func aClassicZipBombIsRefusedByItsCompressionRatio() async throws {
        let zeros = Data(count: 32 << 20)
        let archive = ZipBuilder([ZipBuilder.Entry("zeros.bin", zeros)]).build()
        #expect(archive.count < 64 << 10, "32 MiB compresses to \(archive.count) bytes")
        try await expectRefused(archive, .compressionRatioTooHigh(file: 1, limit: 100))
    }

    @Test func manySmallEntriesThatTogetherFormABombAreRefused() async throws {
        let entries = (0..<24).map { ZipBuilder.Entry("z\($0).bin", Data(count: 1 << 20)) }
        try await expectRefused(ZipBuilder(entries).build(), .archiveRatioTooHigh(limit: 100))
    }

    @Test func aBombThatLiesAboutItsSizeStopsAtTheDeclaredSize() async throws {
        var liar = ZipBuilder.Entry("small.txt", Data(count: 32 << 20))
        liar.declaredSize = 1_024
        try await expectRefused(ZipBuilder([liar]).build(), .expandsBeyondDeclaredSize(file: 1))

        var storedLiar = ZipBuilder.Entry("small.txt", Data(count: 4_096), method: 0)
        storedLiar.declaredSize = 1_024
        try await expectRefused(ZipBuilder([storedLiar]).build(), .expandsBeyondDeclaredSize(file: 1))
    }

    @Test func expansionBeyondTheTotalLimitIsRefused() async throws {
        let limits = ImportLimits(maximumTotalBytes: 1 << 20)
        let random = Data((0..<(600 << 10)).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761 >> 13) })
        let archive = ZipBuilder([ZipBuilder.Entry("a.bin", random, method: 0), ZipBuilder.Entry("b.bin", random, method: 0)]).build()
        try await expectRefused(archive, .expandedSizeTooLarge(limit: 1 << 20), limits: limits)
    }

    @Test func aNestedArchiveIsRefusedByNameAndBySignature() async throws {
        let inner = ZipBuilder([ZipBuilder.Entry("deeper.txt", Data("x".utf8))]).build()
        try await expectRefused(
            ZipBuilder([ZipBuilder.Entry("readme.txt", Data("hi".utf8)), ZipBuilder.Entry("inner.zip", inner, method: 0)]).build(),
            .nestedArchive(file: 2)
        )
        try await expectRefused(
            ZipBuilder([ZipBuilder.Entry("readme.txt", Data("hi".utf8)), ZipBuilder.Entry("notes.txt", inner, method: 0)]).build(),
            .nestedArchive(file: 2)
        )
        let gzip = Data([0x1F, 0x8B, 0x08, 0x00]) + Data(count: 32)
        try await expectRefused(ZipBuilder([ZipBuilder.Entry("photo.jpg", gzip)]).build(), .nestedArchive(file: 1))
    }

    @Test func overlappingEntriesAreRefused() async throws {
        // Entry A's stored data "quotes" entry B's local header and data, so the bytes of B are
        // also the bytes of A: the overlapping construction behind non-recursive zip bombs.
        let bContent = Data("payload".utf8)
        let bHeader = ZipBuilder.localHeader(Array("b.txt".utf8), method: 0, crc: ZipBuilder.crc(bContent),
                                             compressedSize: UInt32(bContent.count), declaredSize: UInt32(bContent.count))
        let aContent = bHeader + bContent
        let aHeader = ZipBuilder.localHeader(Array("a.txt".utf8), method: 0, crc: ZipBuilder.crc(aContent),
                                             compressedSize: UInt32(aContent.count), declaredSize: UInt32(aContent.count))
        let body = aHeader + aContent
        let directory =
            ZipBuilder.centralHeader(ZipBuilder.Entry("a.txt", aContent, method: 0), crc: ZipBuilder.crc(aContent),
                                     compressedSize: UInt32(aContent.count), declaredSize: UInt32(aContent.count), offset: 0)
            + ZipBuilder.centralHeader(ZipBuilder.Entry("b.txt", bContent, method: 0), crc: ZipBuilder.crc(bContent),
                                       compressedSize: UInt32(bContent.count), declaredSize: UInt32(bContent.count),
                                       offset: UInt32(aHeader.count))
        try await expectRefused(ZipBuilder.finish(body: body, directory: directory, count: 2), .overlappingEntries)
    }

    @Test func damagedArchivesAreRefused() async throws {
        var badCRC = ZipBuilder.Entry("a.txt", Data("content".utf8))
        badCRC.crc = 0xDEAD_BEEF
        try await expectRefused(ZipBuilder([badCRC]).build(), .checksumMismatch(file: 1))

        var renamed = ZipBuilder.Entry("a.txt", Data("content".utf8))
        renamed.localName = Array("b.txt".utf8)
        try await expectRefused(ZipBuilder([renamed]).build(), .corruptArchive)

        var short = ZipBuilder.Entry("a.txt", Data("content".utf8), method: 0)
        short.declaredSize = 100
        try await expectRefused(ZipBuilder([short]).build(), .corruptArchive)

        let valid = ZipBuilder([ZipBuilder.Entry("a.txt", Data("content".utf8))]).build()
        try await expectRefused(valid.dropLast(5), .notAnArchive)
        try await expectRefused(Data("PK but not really an archive at all, just text".utf8), .notAnArchive)
        try await expectRefused(Data(), .notAnArchive)
        var garbage = ZipBuilder.Entry("a.txt", Data("content".utf8))
        garbage.method = 8
        let broken = ZipBuilder([garbage]).build()
        var corrupted = broken
        corrupted[30 + 5] ^= 0xFF // the first byte of the deflate stream
        let (_, result) = try await stage(corrupted)
        if case .failure(let rejection) = result {
            #expect(rejection.category == .unsafeArchive)
        } else {
            Issue.record("a corrupted deflate stream was staged")
        }
    }

    @Test func namesThatCollideAreRefused() async throws {
        try await expectRefused(
            ZipBuilder([ZipBuilder.Entry("Read.me", Data("a".utf8)), ZipBuilder.Entry("read.ME", Data("b".utf8))]).build(),
            .duplicatePath(file: 2)
        )
        try await expectRefused(
            ZipBuilder([ZipBuilder.Entry("Caf\u{E9}.txt", Data("a".utf8)), ZipBuilder.Entry("Cafe\u{301}.txt", Data("b".utf8))]).build(),
            .duplicatePath(file: 2)
        )
    }

    @Test func aCancelledExpansionLeavesNothing() async throws {
        let staging = try StagingFixture()
        let url = try staging.directory.file("big.zip", ZipBuilder([
            ZipBuilder.Entry("a.bin", Data(count: 256 << 10)), ZipBuilder.Entry("b.bin", Data(count: 256 << 10)),
        ]).build())
        let area = staging.area
        let task = Task { () async throws -> StagingOutcome in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await area.stageArchive(at: url)
        }
        await #expect(throws: ImportRejection.cancelled) { try await task.value }
        await staging.expectNothingStaged()
    }
}
