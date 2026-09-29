import Foundation
import LabDomain
import Testing

/// CORE-006: path, UTF-8, JSON, and archive-directory policy, run before anything is adopted.
@Suite struct StagingPolicyTests {
    // MARK: Names

    @Test(arguments: try HostileFixtures.nameCases())
    func everyHostileNameIsRefusedWithItsReason(_ hostile: HostileFixtures.NameCase) {
        #expect(throws: hostile.expected) { try StagedPath(bytes: hostile.bytes) }
        let rejection = ImportRejection.unsafePath(file: 3, hostile.expected)
        #expect(rejection.userMessage.hasPrefix("Item 3 "))
        #expect(rejection.code == "unsafe-path/\(hostile.expected.rawValue)")
        expectReadable(rejection)
    }

    @Test func theFixtureCoversEveryPathRejection() throws {
        let covered = Set(try HostileFixtures.nameCases().map(\.expected))
        let untested: Set<PathRejection> = [.empty, .tooLong, .componentTooLong]
        #expect(covered.union(untested) == Set(PathRejection.allCases))
    }

    @Test func lengthAndEmptinessLimitsHold() {
        #expect(throws: PathRejection.empty) { try StagedPath("") }
        #expect(throws: PathRejection.tooLong) { try StagedPath(String(repeating: "a/", count: 600) + "b") }
        #expect(throws: PathRejection.componentTooLong) { try StagedPath(String(repeating: "x", count: 256)) }
        #expect(throws: PathRejection.tooDeep) {
            try StagedPath("a/b/c/escape.txt", limits: ImportLimits(maximumNestingDepth: 3))
        }
    }

    @Test func ordinaryNamesAreAcceptedAndNormalized() throws {
        let decomposed = try StagedPath("Cafe\u{301}/menu.v2.txt")
        #expect(decomposed.value == "Café/menu.v2.txt")
        #expect(decomposed.components == ["Café", "menu.v2.txt"])
        #expect(decomposed.pathExtension == "txt")
        #expect(try StagedPath(".hidden").pathExtension == "")
        #expect(try StagedPath("backup.tar.GZ").pathExtension == "gz")
        #expect(try StagedPath(bytes: Array("folder/".utf8), isDirectory: true).value == "folder")
        #expect(throws: PathRejection.emptyComponent) { try StagedPath("folder/") }
    }

    @Test func aPathNeverPrintsItsName() throws {
        let path = try StagedPath(Sentinels.fileName)
        for text in [path.description, String(describing: path), String(reflecting: path), "\(path)"] {
            #expect(Sentinels.leaks(in: text).isEmpty, "\(text)")
        }
        var dumped = ""
        dump(path, to: &dumped)
        #expect(Sentinels.leaks(in: dumped).isEmpty)
    }

    @Test func namesThatAFileSystemWouldMergeCollide() throws {
        var names = StagedPathSet()
        #expect(names.insert(try StagedPath("Notes/Report.txt"), isDirectory: false))
        #expect(!names.insert(try StagedPath("notes/report.TXT"), isDirectory: false))
        #expect(names.insert(try StagedPath("Cafe\u{301}.txt"), isDirectory: false))
        #expect(!names.insert(try StagedPath("Caf\u{E9}.txt"), isDirectory: false))
        // A file and a folder may not share a name, in either order.
        #expect(!names.insert(try StagedPath("notes"), isDirectory: false))
        #expect(!names.insert(try StagedPath("notes/report.txt/inner"), isDirectory: false))
        #expect(names.insert(try StagedPath(bytes: Array("Notes/".utf8), isDirectory: true), isDirectory: true))
    }

    // MARK: UTF-8

    @Test func strictUTF8RefusesEveryIllFormedSequence() {
        let cases: [([UInt8], Int?)] = [
            (Array("plain ascii and é 日本 😀".utf8), nil),
            ([0x61, 0xC0, 0xAF], 1), // overlong "/"
            ([0xE0, 0x80, 0xAF], 0), // three-byte overlong "/"
            ([0xF0, 0x80, 0x80, 0xAF], 0), // four-byte overlong "/"
            ([0xED, 0xA0, 0x80], 0), // encoded surrogate
            ([0xF4, 0x90, 0x80, 0x80], 0), // above U+10FFFF
            ([0xF8, 0x88, 0x80, 0x80, 0x80], 0), // five-byte form
            ([0x61, 0x80], 1), // stray continuation
            ([0x61, 0xE2, 0x82], 1), // truncated
            ([0xFF], 0),
        ]
        for (bytes, offset) in cases {
            #expect(StrictUTF8.firstInvalidOffset(in: bytes) == offset, "\(bytes)")
        }
    }

    @Test func theMalformedUTF8FixtureIsRefusedAtItsFirstBadByte() throws {
        let data = try HostileFixtures.data("malformed-utf8.txt")
        let expectedOffset = try #require(data.firstIndex(of: 0xC0))
        let rejection = #expect(throws: ImportRejection.self) { try StagingRecord.text(utf8: data) }
        #expect(rejection == .malformedUTF8(offset: expectedOffset))
        expectReadable(rejection)
        #expect(throws: StrictJSONError.invalidUTF8(offset: expectedOffset)) {
            try StrictJSON.validate(data, maximumDepth: 16, maximumBytes: 1_000)
        }
    }

    // MARK: JSON

    @Test func theDeeplyNestedFixtureIsRefused() throws {
        let data = try HostileFixtures.data("deeply-nested.json")
        #expect(throws: StrictJSONError.tooDeep(limit: 16)) { try StrictJSON.validate(data, maximumDepth: 16, maximumBytes: 1 << 20) }
        expectReadable(.malformedJSON(file: 1, .tooDeep(limit: 16)))
        // Foundation accepts it, which is why the strict check runs first.
        #expect((try? JSONSerialization.jsonObject(with: data)) != nil)
    }

    @Test func aHundredThousandLevelsDoNotExhaustTheStack() {
        let depth = 100_000
        let data = Data((String(repeating: "[", count: depth) + String(repeating: "]", count: depth)).utf8)
        #expect(throws: StrictJSONError.tooDeep(limit: 16)) { try StrictJSON.validate(data, maximumDepth: 16, maximumBytes: 1 << 20) }
        // With a generous limit the iterative validator walks all of it.
        #expect(throws: Never.self) { try StrictJSON.validate(data, maximumDepth: depth, maximumBytes: 1 << 20) }
    }

    @Test func exactlySixteenLevelsPass() throws {
        let sixteen = Data((String(repeating: "{\"a\":", count: 15) + "[1]" + String(repeating: "}", count: 15)).utf8)
        try StrictJSON.validate(sixteen, maximumDepth: 16, maximumBytes: 1 << 20)
        let seventeen = Data((String(repeating: "{\"a\":", count: 16) + "[1]" + String(repeating: "}", count: 16)).utf8)
        #expect(throws: StrictJSONError.tooDeep(limit: 16)) { try StrictJSON.validate(seventeen, maximumDepth: 16, maximumBytes: 1 << 20) }
    }

    @Test func theDuplicateKeysFixtureIsRefused() throws {
        let data = try HostileFixtures.data("duplicate-keys.json")
        let error = #expect(throws: StrictJSONError.self) { try StrictJSON.validate(data, maximumDepth: 16, maximumBytes: 1 << 20) }
        guard case .duplicateKey(let offset) = error else {
            Issue.record("expected a duplicate key, got \(String(describing: error))")
            return
        }
        #expect(data[offset] == UInt8(ascii: "\""))
        // Foundation keeps one of the two titles silently.
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((decoded?["item"] as? [String: String])?.count == 2)
        expectReadable(.malformedJSON(file: 1, .duplicateKey(offset: offset)))
    }

    @Test func duplicatesAreFoundThroughEscapesAndCanonicalEquivalence() {
        let cases = [
            #"{"a":1,"a":2}"#,
            #"{"a":1,"\u0061":2}"#,
            #"{"x":{"é":1,"e\u0301":2}}"#,
            #"[{"k":1},{"k":2,"k":3}]"#,
        ]
        for text in cases {
            #expect(throws: StrictJSONError.self, "\(text)") { try StrictJSON.validate(Data(text.utf8), maximumDepth: 16, maximumBytes: 1_000) }
        }
        #expect(throws: Never.self) { try StrictJSON.validate(Data(#"[{"k":1},{"k":2}]"#.utf8), maximumDepth: 16, maximumBytes: 1_000) }
    }

    @Test func malformedJSONIsRefusedWithItsReason() {
        let cases: [(String, StrictJSONError)] = [
            ("", .empty),
            ("\u{FEFF}{}", .invalidSyntax(offset: 0)),
            ("[1,]", .invalidSyntax(offset: 3)),
            ("{\"a\":1,}", .invalidSyntax(offset: 7)),
            ("{\"a\" 1}", .invalidSyntax(offset: 5)),
            ("[01]", .invalidSyntax(offset: 2)),
            ("[1.]", .invalidSyntax(offset: 3)),
            ("\"tab\there\"", .invalidSyntax(offset: 4)),
            ("[\"\\x\"]", .invalidSyntax(offset: 2)),
            ("[\"\\ud800\"]", .unpairedSurrogate(offset: 2)),
            ("[\"\\udc00\"]", .unpairedSurrogate(offset: 2)),
            ("[\"\\ud800\\u0041\"]", .unpairedSurrogate(offset: 2)),
            ("// comment\n{}", .invalidSyntax(offset: 0)),
            ("{} {}", .invalidSyntax(offset: 3)),
            ("[tru]", .invalidSyntax(offset: 1)),
        ]
        for (text, expected) in cases {
            #expect(throws: expected, "\(text)") { try StrictJSON.validate(Data(text.utf8), maximumDepth: 16, maximumBytes: 1_000) }
        }
        #expect(throws: StrictJSONError.tooLarge(limit: 4)) { try StrictJSON.validate(Data("[1,2]".utf8), maximumDepth: 16, maximumBytes: 4) }
    }

    @Test func validJSONPasses() throws {
        let text = #" { "a" : [1, -2.5e+3, 0.25, true, false, null, "\ud83d\ude00 \" \\ \/ \b\f\n\r\t"], "b": {}, "c": [] } "#
        try StrictJSON.validate(Data(text.utf8), maximumDepth: 16, maximumBytes: 1_000)
    }

    // MARK: Archive directories

    private func file(_ name: String, size: Int = 10, compressed: Int? = nil) -> ArchiveEntry {
        ArchiveEntry(nameBytes: Array(name.utf8), kind: .file, compressedSize: compressed ?? size, declaredSize: size, isEncrypted: false)
    }

    @Test func anOrdinaryDirectoryPlansItsFiles() throws {
        let entries = [
            ArchiveEntry(nameBytes: Array("notes/".utf8), kind: .directory, compressedSize: 0, declaredSize: 0, isEncrypted: false),
            file("notes/a.txt", size: 100, compressed: 40),
            file("manifest.anlab", size: 50),
        ]
        let plan = try ArchivePolicy.plan(entries, limits: .standard)
        #expect(plan.files.map(\.entryIndex) == [1, 2])
        #expect(plan.files.map(\.path.value) == ["notes/a.txt", "manifest.anlab"])
        #expect(plan.totalDeclaredSize == 150)
    }

    @Test func everyDangerousDirectoryIsRefusedBeforeExpansion() {
        let limits = ImportLimits.standard
        func refused(_ entries: [ArchiveEntry], limits: ImportLimits = limits) -> ImportRejection? {
            do {
                _ = try ArchivePolicy.plan(entries, limits: limits)
                return nil
            } catch {
                return error
            }
        }
        let tooMany = (0...2_000).map { file("f\($0).txt") }
        #expect(refused(tooMany) == .tooManyEntries(limit: 2_000))
        #expect(refused([file("ok.txt"), ArchiveEntry(nameBytes: Array("l".utf8), kind: .link, compressedSize: 5, declaredSize: 5, isEncrypted: false)])
            == .linkEntry(file: 2))
        #expect(refused([ArchiveEntry(nameBytes: Array("fifo".utf8), kind: .other, compressedSize: 0, declaredSize: 0, isEncrypted: false)])
            == .unsupportedEntryType(file: 1))
        #expect(refused([ArchiveEntry(nameBytes: Array("s.txt".utf8), kind: .file, compressedSize: 5, declaredSize: 5, isEncrypted: true)])
            == .unsupportedArchive(.encryption))
        #expect(refused([file("ok.txt"), file("../escape.txt")]) == .unsafePath(file: 2, .parentReference))
        #expect(refused([file("inner.zip")]) == .nestedArchive(file: 1))
        #expect(refused([file("inner.ANLABPACK")]) == .nestedArchive(file: 1))
        #expect(refused([file("Read.me"), file("read.ME")]) == .duplicatePath(file: 2))
        #expect(refused([file("a"), file("a/b")]) == .duplicatePath(file: 2))
        let bomb = file("zeros.bin", size: 64 << 20, compressed: 64 << 10)
        #expect(refused([bomb]) == .compressionRatioTooHigh(file: 1, limit: 100))
        let huge = file("huge.bin", size: (1 << 30) + 1, compressed: 1 << 29)
        #expect(refused([huge]) == .expandedSizeTooLarge(limit: 1 << 30))
        let parts = (0..<3).map { file("part\($0).bin", size: 400 << 20, compressed: 200 << 20) }
        #expect(refused(parts) == .expandedSizeTooLarge(limit: 1 << 30))
        // Each entry stays under the ratio floor, but together they are a bomb.
        let spread = (0..<40).map { file("z\($0).bin", size: 1 << 20, compressed: 256) }
        #expect(refused(spread, limits: ImportLimits(maximumFiles: 32)) == .archiveRatioTooHigh(limit: 100))
        #expect(refused((0..<33).map { file("f\($0).txt") }) == .tooManyFiles(limit: 32))
    }

    @Test func signaturesOfNestedArchivesAreRecognized() {
        let archives: [[UInt8]] = [
            [0x50, 0x4B, 0x03, 0x04, 0x14], [0x50, 0x4B, 0x05, 0x06], [0x1F, 0x8B, 0x08], [0x42, 0x5A, 0x68, 0x39],
            [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00], [0x28, 0xB5, 0x2F, 0xFD], [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C],
            [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00], Array("AA01".utf8), Array("xar!".utf8),
            [UInt8](repeating: 0, count: 257) + Array("ustar".utf8),
        ]
        for bytes in archives { #expect(ArchivePolicy.looksLikeArchive(bytes), "\(bytes.prefix(6))") }
        #expect(!ArchivePolicy.looksLikeArchive(Array("PK is also how this note starts".utf8)))
        #expect(!ArchivePolicy.looksLikeArchive(Array("{\"json\": true}".utf8)))
    }

    // MARK: Limits

    @Test func limitsOnlyNarrow() {
        let wider = ImportLimits(maximumFiles: 10_000, maximumTotalBytes: .max, maximumArchiveEntries: 1_000_000, maximumNestingDepth: 1_000)
        #expect(wider == .standard)
        let narrow = ImportLimits(maximumFiles: 4, maximumTextBytes: 1_024)
        let combined = ImportLimits.standard.narrowed(to: narrow)
        #expect(combined.maximumFiles == 4 && combined.maximumTextBytes == 1_024)
        #expect(combined.maximumTotalBytes == ImportLimits.standard.maximumTotalBytes)
        #expect(narrow.narrowed(to: .standard) == combined)
        #expect(ImportLimits(maximumFiles: 0).maximumFiles == 1)
        // The documented defaults (docs/DATA_CONTRACTS.md, "Import resource policy").
        let standard = ImportLimits.standard
        #expect(standard.maximumFiles == 32)
        #expect(standard.maximumTextBytes == 2 * 1_024 * 1_024)
        #expect(standard.maximumTotalBytes == 1_024 * 1_024 * 1_024)
        #expect(standard.maximumArchiveEntries == 2_000)
        #expect(standard.maximumNestingDepth == 16)
    }
}
