import Foundation
import LabDomain
import Testing
@testable import PortableObjects

/// The `.anlab` document on its own: canonical form, lossless round trips, and refusals.
@Suite struct DocumentCodecTests {
    // MARK: Round trips

    @Test func theBundledSampleIsAlreadyCanonical() throws {
        let sample = try Fixture.sample
        let document = try LabDocument(decoding: sample)
        #expect(document.encoded() == sample)
        #expect(document.itemID == Fixture.sampleID)
    }

    @Test func readingAndWritingKeepsEveryFieldIncludingOnesThisBuildDoesNotKnow() throws {
        let document = try LabDocument(decoding: Fixture.sample)
        let again = try LabDocument(decoding: document.encoded())
        #expect(again == document)
        #expect(again.encoded() == document.encoded())
        // A top-level field, a member of `fields`, and every value in `extras` survive.
        #expect(again.root["x-lab-note"]?.stringValue?.hasPrefix("A field this version does not know") == true)
        #expect(again.root["fields"]?.objectValue?["glazeCone"] == .number("6"))
        #expect(again.root["fields"]?.objectValue?["firing"] == .null)
        let extras = try #require(again.root["extras"]?.objectValue)
        #expect(extras["zero"] == .number("0"))
        #expect(extras["empty"] == .string(""))
        #expect(extras["flag"] == .bool(false))
        #expect(extras["surface"]?.objectValue?["gloss"] == .number("0.0"))
        #expect(again.unknownFieldCount == 3)
        #expect(again.extrasCount == 5)
    }

    @Test func unicodeKeepsItsExactScalarsWithNoNormalization() throws {
        let document = try LabDocument(decoding: Fixture.sample)
        // "crème" is written with a combining grave accent (e + U+0300), not the precomposed è.
        #expect(document.title.unicodeScalars.contains("\u{0300}"))
        #expect(!document.title.unicodeScalars.contains("\u{00E8}"))
        #expect(document.title.unicodeScalars.contains("\u{1F9EA}"))

        // Escapes, including a surrogate pair, read as their characters and are written raw.
        let escaped = Fixture.minimal(title: #"crème 🧪 שלום"#)
        let decoded = try LabDocument(decoding: escaped)
        #expect(decoded.title.bytes == "crème 🧪 שלום".precomposedStringWithCanonicalMapping.bytes)
        #expect(decoded.canonicalText.contains("\"title\": \"crème 🧪 שלום\""))

        // Canonically equivalent spellings are different documents, byte for byte.
        let precomposed = try LabDocument(decoding: Fixture.minimal(id: Fixture.sampleID.rawValue, title: "cr\u{E8}me"))
        let decomposed = try LabDocument(decoding: Fixture.minimal(id: Fixture.sampleID.rawValue, title: "cre\u{300}me"))
        #expect(precomposed != decomposed)
        #expect(precomposed.encoded() != decomposed.encoded())
    }

    @Test(arguments: [
        (#","fields":{"note":""}"#, LabDocument.NoteField.text("")),
        (#","fields":{"note":null}"#, .null),
        (#","fields":{}"#, .absent),
        ("", .absent),
    ])
    func emptyNullAndAbsentNotesStayDistinct(fields: String, expected: LabDocument.NoteField) throws {
        let data = Fixture.minimal(id: Fixture.sampleID.rawValue, extra: fields)
        let document = try LabDocument(decoding: data)
        #expect(document.note == expected)
        let again = try LabDocument(decoding: document.encoded())
        #expect(again.note == expected)
        #expect(again == document)
        // Absent `fields` stays absent; an empty `fields` stays present.
        #expect((again.root["fields"] != nil) == fields.contains("fields"))
    }

    @Test func numbersKeepTheLiteralTheyWereWrittenAs() throws {
        let literals = ["0", "-0", "0.0", "1.50", "1e2", "2.5E-3", "12345678901234567890123", "-7"]
        let extras = literals.enumerated().map { #""n\#($0.offset)":\#($0.element)"# }.joined(separator: ",")
        let document = try LabDocument(decoding: Fixture.minimal(extra: #","extras":{\#(extras)}"#))
        let again = try LabDocument(decoding: document.encoded())
        for (index, literal) in literals.enumerated() {
            #expect(again.root["extras"]?.objectValue?["n\(index)"] == .number(literal))
        }
    }

    @Test func theCanonicalFormPutsSchemaFieldsFirstAndSortsTheRest() throws {
        let data = Fixture.minimal(extra: #","zeta":1,"alpha":{"b":2,"a":1},"revision":3"#)
        let text = try LabDocument(decoding: data).canonicalText
        let order = ["\"format\"", "\"schemaVersion\"", "\"documentID\"", "\"kind\"", "\"revision\"", "\"title\"", "\"alpha\"", "\"zeta\""]
        let positions = order.map { text.range(of: $0)?.lowerBound }
        #expect(positions.allSatisfy { $0 != nil })
        #expect(positions.compactMap(\.self) == positions.compactMap(\.self).sorted())
        #expect(text.contains("\"a\": 1,\n    \"b\": 2"))
        #expect(text.hasSuffix("}\n"))
    }

    @Test func thePlainTextSummarySaysItIsLossy() throws {
        let document = try LabDocument(decoding: Fixture.sample)
        #expect(document.plainText.hasPrefix(document.title + "\n"))
        #expect(document.plainText.contains("Identifier: F1586771-0F15-4044-A372-5F9BC9968FDB"))
        #expect(document.plainText.contains("This text is a summary"))
    }

    // MARK: Refusals

    static let refusals: [(String, String, PortableObjectError)] = [
        ("not JSON", "{title: nope}", .staging(.malformedJSON(file: 1, .invalidSyntax(offset: 1)))),
        ("an array", "[]", .notALabObject),
        ("no format", #"{"schemaVersion":1}"#, .notALabObject),
        ("another format", #"{"format":"native-lab-item","schemaVersion":1}"#, .notALabObject),
        ("a newer schema", #"{"format":"native-lab-object","schemaVersion":2}"#, .newerSchema(found: 2, supported: 1)),
        ("schema zero", #"{"format":"native-lab-object","schemaVersion":0}"#, .unsupportedSchema),
        ("a text schema", #"{"format":"native-lab-object","schemaVersion":"1"}"#, .wrongType(.schemaVersion)),
        ("no schema", #"{"format":"native-lab-object"}"#, .missingField(.schemaVersion)),
        ("no ID", #"{"format":"native-lab-object","schemaVersion":1,"kind":"collection-item","title":"T"}"#, .missingField(.documentID)),
    ]

    @Test(arguments: refusals)
    func malformedDocumentsAreRefused(name: String, text: String, expected: PortableObjectError) {
        #expect(throws: expected, "\(name)") { try LabDocument(decoding: Data(text.utf8)) }
    }

    static let fieldRefusals: [(String, String, PortableObjectError)] = [
        ("a bad identifier", #","documentID":"not-a-uuid""#, .invalidDocumentID),
        ("another kind", #","kind":"collection""#, .unsupportedKind),
        ("revision zero", #","revision":0"#, .invalidRevision),
        ("a fractional revision", #","revision":1.5"#, .invalidRevision),
        ("an empty title", #","title":"   ""#, .invalidTitle(.emptyTitle)),
        ("a title with a line break", #","title":"a\nb""#, .invalidTitle(.controlCharacter(in: .title))),
        ("a numeric title", #","title":7"#, .wrongType(.title)),
        ("a numeric note", #","fields":{"note":7}"#, .wrongType(.note)),
        ("a note with a bell", #","fields":{"note":"ding\u0007"}"#, .invalidNote(.controlCharacter(in: .note))),
        ("fields as a list", #","fields":[]"#, .wrongType(.fields)),
        ("extras as text", #","extras":"x""#, .wrongType(.extras)),
        ("provenance as a number", #","provenance":1"#, .wrongType(.provenance)),
        ("a grant", #","grant":{"operations":["reset-demo"]}"#, .authorityField),
        ("a scope, capitalized", #","Scope":"commit-destructive""#, .authorityField),
        ("a bookmark", #","bookmarkData":"AAAA""#, .authorityField),
        ("attachments as an object", #","attachments":{}"#, .wrongType(.attachments)),
    ]

    /// Each case replaces or adds one field of an otherwise valid document.
    @Test(arguments: fieldRefusals)
    func invalidFieldsAreRefused(name: String, member: String, expected: PortableObjectError) throws {
        let base = #"{"format":"native-lab-object","schemaVersion":1,"documentID":"\#(UUID().uuidString)","kind":"collection-item","title":"T""#
        var object = try JSONSerialization.jsonObject(with: Data((base + "}").utf8)) as! [String: Any]
        let change = try JSONSerialization.jsonObject(with: Data(("{" + member.dropFirst() + "}").utf8)) as! [String: Any]
        object.merge(change) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: expected, "\(name)") { try LabDocument(decoding: data) }
    }

    static let attachmentRefusals: [(String, String, PortableObjectError)] = [
        ("a parent-folder path", #"[{"path":"../../secrets.txt","byteCount":3,"sha256":"\#(digest)"}]"#,
         .unsafeAttachmentPath(position: 1, .parentReference)),
        ("an absolute path", #"[{"path":"/etc/hosts","byteCount":3,"sha256":"\#(digest)"}]"#,
         .unsafeAttachmentPath(position: 1, .absolute)),
        ("a fullwidth slash", #"[{"path":"assets／..／x","byteCount":3,"sha256":"\#(digest)"}]"#,
         .unsafeAttachmentPath(position: 1, .lookalikeSeparator)),
        ("a second path that only differs in case",
         #"[{"path":"assets/a.png","byteCount":1,"sha256":"\#(digest)"},{"path":"assets/A.png","byteCount":1,"sha256":"\#(digest)"}]"#,
         .duplicateAttachmentPath(position: 2)),
        ("no digest", #"[{"path":"assets/a.png","byteCount":1}]"#, .invalidAttachment(position: 1)),
        ("a negative size", #"[{"path":"assets/a.png","byteCount":-1,"sha256":"\#(digest)"}]"#, .invalidAttachment(position: 1)),
    ]

    static let digest = String(repeating: "ab", count: 32)

    @Test(arguments: attachmentRefusals)
    func unsafeAttachmentsAreRefused(name: String, attachments: String, expected: PortableObjectError) {
        let data = Fixture.minimal(extra: #","attachments":\#(attachments)"#)
        #expect(throws: expected, "\(name)") { try LabDocument(decoding: data) }
    }

    @Test func moreThanThirtyTwoAttachmentsAreRefused() {
        let list = (0...32).map { #"{"path":"assets/\#($0).png","byteCount":1,"sha256":"\#(Self.digest)"}"# }.joined(separator: ",")
        #expect(throws: PortableObjectError.tooManyAttachments(limit: 32)) {
            try LabDocument(decoding: Fixture.minimal(extra: #","attachments":[\#(list)]"#))
        }
    }

    @Test func safeAttachmentsAreReadAndKept() throws {
        let data = Fixture.minimal(extra: #","attachments":[{"path":"assets/glaze.png","byteCount":12,"sha256":"\#(Self.digest)","mediaType":"image/png","x-future":true}]"#)
        let document = try LabDocument(decoding: data)
        #expect(document.attachments.count == 1)
        #expect(document.attachments[0].path.value == "assets/glaze.png")
        #expect(try LabDocument(decoding: document.encoded()) == document)
        #expect(document.encoded().count > 0 && String(decoding: document.encoded(), as: UTF8.self).contains("\"x-future\": true"))
    }

    @Test func duplicateKeysNestingAndSizeAreRefusedBeforeAnyDecoderRuns() {
        let duplicate = Data(#"{"format":"native-lab-object","format":"native-lab-object"}"#.utf8)
        #expect(throws: PortableObjectError.staging(.malformedJSON(file: 1, .duplicateKey(offset: 30)))) {
            try LabDocument(decoding: duplicate)
        }
        let deep = Fixture.minimal(extra: #","extras":"# + String(repeating: #"{"a":"#, count: 16) + "1" + String(repeating: "}", count: 16))
        #expect(throws: PortableObjectError.staging(.malformedJSON(file: 1, .tooDeep(limit: 16)))) { try LabDocument(decoding: deep) }
        let limit = ImportLimits.standard.maximumTextBytes
        let large = Fixture.minimal(extra: #","extras":{"pad":""# + String(repeating: "x", count: limit) + #""}"#)
        #expect(throws: PortableObjectError.staging(.malformedJSON(file: 1, .tooLarge(limit: limit)))) { try LabDocument(decoding: large) }
    }

    /// Every refusal is a sentence a person can act on. It names only schema fields and positions,
    /// never a value or a field the document invented, and it says nothing was imported.
    @Test func refusalMessagesAreReadableAndContentFree() throws {
        let invented = #"{"format":"native-lab-object","schemaVersion":1,"documentID":"x","kind":"collection-item","title":"T","grant-me-SECRET":1}"#
        do {
            _ = try LabDocument(decoding: Data(invented.utf8))
            Issue.record("expected a refusal")
        } catch {
            #expect(!error.userMessage.contains("SECRET"))
        }
        let errors: [PortableObjectError] = Self.refusals.map(\.2) + Self.fieldRefusals.map(\.2) + Self.attachmentRefusals.map(\.2) + [
            .attachmentsNotSupported(count: 2), .extrasTooLarge(limit: 65_536), .noDestination, .destinationUnavailable,
            .changedSinceReview, .stateChanged, .nothingToImport, .storedCopyArchived, .cancelled, .notAuthorized,
            .identifierConflict, .storeUnavailable, .unavailable,
            .staging(.malformedJSON(file: 1, .tooLarge(limit: 2 << 20))), .staging(.unreadableSource(file: 1)),
        ]
        for error in errors {
            #expect(error.userMessage.hasSuffix(".") && error.userMessage.count > 20, "\(error.code)")
            #expect(error.userMessage.contains("Nothing") || error.userMessage.contains("nothing") || error.userMessage.contains("Import it again"),
                    "\(error.code)")
            #expect(!error.code.contains(" "))
        }
        #expect(PortableObjectError.staging(.malformedJSON(file: 1, .tooLarge(limit: 2 << 20))).userMessage
            == "The document is larger than 2 MB, the most a lab object can be. Nothing was imported.")
    }
}
