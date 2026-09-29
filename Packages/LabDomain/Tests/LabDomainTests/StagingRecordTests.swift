import Foundation
import LabDomain
import Testing

/// CORE-006: the durable staging record is validated when it is made and again, from its bytes,
/// when the app reads it back.
@Suite struct StagingRecordTests {
    private let stagedAt = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func everyPayloadRoundTripsThroughItsEncoding() throws {
        let files = [
            StagedFile(path: try StagedPath("notes/a.txt"), byteCount: 3, sha256: .sha256(Data("abc".utf8))),
            StagedFile(path: try StagedPath("b.json"), byteCount: 2, sha256: .sha256(Data("{}".utf8))),
        ]
        let payloads: [StagedPayload] = [
            .text("Line one\n\tLine “two” with \"quotes\" and \\ backslash, 日本語 😀"),
            .link(try #require(URL(string: "https://example.com/page?q=1#part")), title: "A page"),
            .link(try #require(URL(string: "http://example.org/")), title: nil),
            .files(files),
        ]
        for payload in payloads {
            let record = try StagingRecord(payload: payload, stagedAt: stagedAt)
            let decoded = try StagingRecord(decoding: record.encoded())
            #expect(decoded == record)
            #expect(decoded.id == record.id)
        }
    }

    @Test func identicalContentHasOneIdentityWhateverTheTime() throws {
        let first = try StagingRecord(payload: .text("Same"), stagedAt: stagedAt)
        let later = try StagingRecord(payload: .text("Same"), stagedAt: stagedAt.addingTimeInterval(3_600))
        let other = try StagingRecord(payload: .text("Same "), stagedAt: stagedAt)
        #expect(first.digest == later.digest && first.id == later.id)
        #expect(first.digest != other.digest && first.id != other.id)
        // Length prefixes keep a link and its title from merging into another link.
        let url = try #require(URL(string: "https://example.com/a"))
        let split = try StagingRecord(payload: .link(url, title: "b"))
        let joined = try StagingRecord(payload: .link(try #require(URL(string: "https://example.com/a1b")), title: nil))
        #expect(split.digest != joined.digest)
    }

    @Test func theForgedRecordFixtureIsRefused() throws {
        let data = try HostileFixtures.data("forged-staging-record.json")
        let rejection = #expect(throws: ImportRejection.self) { try StagingRecord(decoding: data) }
        #expect(rejection == .unknownRecordField)
        expectReadable(rejection)
    }

    @Test func smuggledFieldsAnywhereAreRefused() throws {
        let record = try StagingRecord(payload: .text("Plain note"), stagedAt: stagedAt)
        let base = try #require(try JSONSerialization.jsonObject(with: record.encoded()) as? [String: Any])
        let injections: [(String, (inout [String: Any]) -> Void)] = [
            ("top-level grant", { $0["grants"] = ["commit-destructive"] }),
            ("top-level adapter", { $0["adapter"] = "app-ui" }),
            ("payload scope", { object in
                var payload = object["payload"] as! [String: Any]
                payload["actorScope"] = ["adapter": "app-ui"]
                object["payload"] = payload
            }),
            ("payload of another kind", { object in
                var payload = object["payload"] as! [String: Any]
                payload["url"] = "https://example.com"
                object["payload"] = payload
            }),
            ("unknown kind", { object in object["payload"] = ["kind": "operation", "text": "archive"] }),
        ]
        for (name, inject) in injections {
            var object = base
            inject(&object)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            #expect(throws: ImportRejection.unknownRecordField, "\(name)") { try StagingRecord(decoding: data) }
        }
    }

    @Test func damagedOrAlteredRecordsAreRefused() throws {
        let record = try StagingRecord(payload: .text("Original"), stagedAt: stagedAt)
        let text = String(decoding: record.encoded(), as: UTF8.self)
        let cases: [(String, ImportRejection)] = [
            (text.replacingOccurrences(of: "Original", with: "Altered!"), .digestMismatch),
            (text.replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":2"), .unsupportedRecordVersion(2)),
            (text.replacingOccurrences(of: "native-lab-staging-record", with: "something-else"), .unsupportedRecordFormat),
            (String(text.dropLast(3)), .malformedRecord(.invalidSyntax(offset: text.utf8.count - 3))),
            (text.replacingOccurrences(of: "\"kind\":\"text\"", with: "\"kind\":\"text\",\"kind\":\"text\""), .malformedRecord(nil)),
            (text.replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":true"), .malformedRecord(nil)),
        ]
        for (altered, expected) in cases {
            let rejection = #expect(throws: ImportRejection.self) { try StagingRecord(decoding: Data(altered.utf8)) }
            switch (expected, rejection) {
            case (.malformedRecord(nil), .malformedRecord?):
                break
            default:
                #expect(rejection == expected, "\(altered)")
            }
        }
        let oversized = Data(count: ImportLimits.standard.maximumRecordBytes + 1)
        #expect(throws: ImportRejection.recordTooLarge(limit: ImportLimits.standard.maximumRecordBytes)) {
            try StagingRecord(decoding: oversized)
        }
    }

    @Test func textRules() throws {
        #expect(throws: ImportRejection.emptyContent) { try StagingRecord(payload: .text(" \n\t ")) }
        #expect(throws: ImportRejection.unsupportedCharacters) { try StagingRecord(payload: .text("bell \u{7}")) }
        let limit = ImportLimits.standard.maximumTextBytes
        #expect(throws: ImportRejection.textTooLarge(limit: limit)) {
            try StagingRecord(payload: .text(String(repeating: "x", count: limit + 1)))
        }
        #expect(throws: ImportRejection.textTooLarge(limit: limit)) {
            try StagingRecord.text(utf8: Data(repeating: 0x61, count: limit + 1))
        }
        expectReadable(.textTooLarge(limit: limit))
        // Right-to-left text and line breaks are content, and are kept.
        _ = try StagingRecord(payload: .text("שלום\r\nעולם\u{200F}"))
    }

    @Test func linkRules() throws {
        func link(_ text: String, title: String? = nil) throws -> StagingRecord {
            try StagingRecord(payload: .link(try #require(URL(string: text)), title: title))
        }
        #expect(throws: ImportRejection.unsupportedLinkScheme) { try link("file:///etc/hosts") }
        #expect(throws: ImportRejection.unsupportedLinkScheme) { try link("javascript:alert(1)") }
        #expect(throws: ImportRejection.unsupportedLinkScheme) { try link("data:text/html,hi") }
        #expect(throws: ImportRejection.unsupportedLinkScheme) { try link("nativelab://grant?scope=all") }
        #expect(throws: ImportRejection.linkContainsCredentials) { try link("https://user:\(Sentinels.token)@example.com/") }
        #expect(throws: ImportRejection.malformedLink) { try link("https:///path-only") }
        #expect(throws: ImportRejection.linkTooLong(limit: 2_000)) { try link("https://example.com/" + String(repeating: "a", count: 2_000)) }
        #expect(throws: ImportRejection.unsupportedCharacters) { try link("https://example.com/", title: "a\u{0}b") }
        #expect(throws: ImportRejection.titleTooLong(limit: 1_024)) { try link("https://example.com/", title: String(repeating: "t", count: 1_025)) }
        _ = try link("HTTPS://Example.com/Path")
    }

    @Test func fileListRules() throws {
        let digest = ContentDigest.sha256(Data())
        func files(_ names: [String], size: Int = 1) throws -> StagedPayload {
            .files(try names.map { StagedFile(path: try StagedPath($0), byteCount: size, sha256: digest) })
        }
        #expect(throws: ImportRejection.noFiles) { try StagingRecord(payload: .files([])) }
        #expect(throws: ImportRejection.duplicatePath(file: 2)) { try StagingRecord(payload: try files(["A.txt", "a.TXT"])) }
        #expect(throws: ImportRejection.tooManyFiles(limit: 32)) { try StagingRecord(payload: try files((0...32).map { "f\($0)" })) }
        #expect(throws: ImportRejection.totalSizeTooLarge(limit: 1 << 30)) { try StagingRecord(payload: try files(["a", "b"], size: 1 << 29 + 1)) }
        let narrow = ImportLimits(maximumNestingDepth: 1)
        #expect(throws: ImportRejection.unsafePath(file: 1, .tooDeep)) { try StagingRecord(payload: try files(["a/b"]), limits: narrow) }
    }

    @Test func aRecordNeverPrintsItsContent() throws {
        let url = try #require(URL(string: "https://\(Sentinels.host)/\(Sentinels.token)"))
        let records = [
            try StagingRecord(payload: .text(Sentinels.content + " " + Sentinels.prompt)),
            try StagingRecord(payload: .link(url, title: Sentinels.pageTitle)),
            try StagingRecord(payload: .files([StagedFile(path: try StagedPath(Sentinels.fileName), byteCount: 1, sha256: .sha256(Data()))])),
        ]
        for record in records {
            var dumped = ""
            dump(record, to: &dumped)
            for text in ["\(record)", String(reflecting: record), "\(record.payload)", dumped] {
                #expect(Sentinels.leaks(in: text).isEmpty, "\(text)")
            }
        }
    }

    @Test func everyRejectionHasAReadableMessageAndAContentFreeCode() {
        let samples: [ImportRejection] = [
            .cancelled, .notFound, .stagingUnavailable, .unreadableSource(file: 1), .unsupportedFileType(file: 1), .emptyContent,
            .textTooLarge(limit: 1), .malformedUTF8(offset: 1), .unsupportedCharacters, .titleTooLong(limit: 1), .linkTooLong(limit: 1),
            .unsupportedLinkScheme, .malformedLink, .linkContainsCredentials, .noFiles, .tooManyFiles(limit: 1),
            .totalSizeTooLarge(limit: 1), .unsafePath(file: 1, .nul), .duplicatePath(file: 1), .malformedJSON(file: 1, .empty),
            .notAnArchive, .unsupportedArchive(.zip64), .tooManyEntries(limit: 1), .linkEntry(file: 1), .unsupportedEntryType(file: 1),
            .nestedArchive(file: 1), .expandedSizeTooLarge(limit: 1), .compressionRatioTooHigh(file: 1, limit: 1),
            .archiveRatioTooHigh(limit: 1), .expandsBeyondDeclaredSize(file: 1), .overlappingEntries, .corruptArchive,
            .checksumMismatch(file: 1), .recordTooLarge(limit: 1), .malformedRecord(nil), .unsupportedRecordFormat,
            .unsupportedRecordVersion(2), .unknownRecordField, .digestMismatch, .linkedFileInStaging, .unexpectedFileInStaging,
            .missingStagedFile(file: 1), .stagedFileChanged(file: 1), .attachmentsNotAdoptable, .textTooLongForNote(limit: 1),
            .grantMissing, .grantExpired, .grantOutOfScope, .notAuthorized, .destinationUnavailable, .identifierConflict,
            .storeUnavailable,
        ] + ArchiveFeature.allCases.map(ImportRejection.unsupportedArchive)
        for sample in samples {
            expectReadable(sample)
            #expect(sample.description == sample.code)
            #expect(sample.code.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-" || $0 == "/") }, "\(sample.code)")
        }
    }
}
