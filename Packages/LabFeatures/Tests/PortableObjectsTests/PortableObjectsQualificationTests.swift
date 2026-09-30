import CryptoKit
import Foundation
import LabDomain
import Testing
@testable import PortableObjects

// LAB-008-B qualification: the experiment's three acceptance criteria, pushed past the cases
// LAB-008-A covered, and step 3 (denial, cancellation, stale and duplicate state, and Reset Demo
// beside imported data). Fixture path: an in-memory store behind `OperationService` with
// `GrantAuthorizationPolicy`, and a real `StagingArea` in a temporary folder. The Mac hosted tests
// repeat the round trip and the refusals through SQLite and the host's own session
// (`PortableObjectsQualificationHostTests`, `PortableObjectsHostEvidenceTests`).

/// Documents and helpers for the qualification suites.
enum Qualification {
    static let digest = String(repeating: "ab", count: 32)

    /// SHA-256 of `Fixtures/LAB-008/traversal-attachment.anlab`. The Mac hosted evidence test pins
    /// the same value for the copy it carries, because the sandboxed app cannot read the repository.
    static let traversalFixtureSHA256 = "49905ccd9317ff9c381533953a7735e20d82e4783e76a6ba52c830ffa7cf591a"

    /// A document as raw JSON text: the required members, then `members` as written. Nothing is
    /// normalized or escaped here, so a member can carry JSON escapes that only the reader decodes.
    static func raw(id: UUID = UUID(), title: String = "Qualification object", revision: Int? = 1, members: String = "") -> Data {
        let revisionMember = revision.map { #","revision":\#($0)"# } ?? ""
        let text = #"{"format":"native-lab-object","schemaVersion":1,"documentID":"\#(id.uuidString)","kind":"collection-item"\#(revisionMember),"title":\#(PortableValue.string(title).compactText())\#(members)}"#
        return Data(text.utf8)
    }

    /// The canonical bytes of a valid document.
    static func canonical(id: UUID = UUID(), title: String, revision: Int? = 1, members: String = "") throws -> Data {
        try LabDocument(decoding: raw(id: id, title: title, revision: revision, members: members)).encoded()
    }

    /// Imports `bytes` into a fresh lab and exports the object; imports that export into a second
    /// fresh lab and exports again.
    static func roundTrip(_ bytes: Data) async throws -> (first: Data, second: Data) {
        let document = try LabDocument(decoding: bytes)
        let first = try await TestLab.make("round-trip-first")
        try await first.importCreating(bytes)
        let exported = try await first.export(document.itemID)
        let second = try await TestLab.make("round-trip-second")
        try await second.importCreating(exported)
        return (exported, try await second.export(document.itemID))
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func temporaryFile(_ data: Data, named name: String = "object.anlab") throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "PortableObjectsQualification-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try data.write(to: url)
        return url
    }

    /// The kind of plan, without the stored item, for comparisons across labs.
    static func kind(_ plan: ImportPlan) -> String {
        switch plan {
        case .create: "create"
        case .alreadyPresent: "already-present"
        case .differs: "differs"
        case .refused(let reason, _): "refused \(reason.code)"
        }
    }
}

extension TestLab {
    /// The seed `TestLab` starts from, rebuilt for another Reset Demo.
    static func seed() throws -> DemoSeed {
        try DemoSeed(
            version: 1,
            collections: [CollectionDraft(id: demoCollection, title: EntityTitle("Swatches"))],
            items: [ItemDraft(id: demoItem, in: demoCollection, title: EntityTitle("Amber"), note: ItemNote("Warm."))]
        )
    }

    /// Reset Demo as the app UI, with the one-operation grant a person's confirmation issues.
    @discardableResult
    func resetDemo() async throws -> ActionReceipt {
        try await perform(.resetDemo(seed: Self.seed()))
    }

    /// Items with this ID, archived or not. A duplicate would make this more than one.
    func count(_ id: ItemID) async -> Int {
        await store.items(in: nil).filter { $0.id == id }.count
    }
}

// MARK: - Criterion 1: Unicode and empty optional fields round-trip

@Suite struct UnicodeAndEmptyFieldRoundTripQualification {
    static let titles: [String] = [
        "cre\u{300}me bru\u{302}le\u{301}e",
        "cr\u{E8}me br\u{FB}l\u{E9}e",
        "釉薬の試し · 유약 · שלום · مرحبا",
        "👩🏽‍🔬 at the kiln 🧪",
        "𝔘𝔫𝔦𝔠𝔬𝔡𝔢 𐍈 😀",
        "\u{212B}ngstr\u{F6}m and \u{C5}ngstro\u{308}m",
        "Ｆｕｌｌｗｉｄｔｈ／ｔｉｔｌｅ",
        "Line\u{2028}separator",
    ]

    static let noteForms: [String] = [
        #","fields":{"note":""}"#,
        #","fields":{"note":null}"#,
        #","fields":{}"#,
        "",
        #","fields":{"note":"Zweite Zeile\nsecond line\r\nthird\ttabbed \u2028 🧪 שלום e\u0301"}"#,
    ]

    /// Every title with every form of the note: empty text, `null`, absent from an empty `fields`,
    /// no `fields` at all, and text with line breaks, a tab, and mixed scripts. Export, import into
    /// a fresh lab, export again: the same bytes, and the title's exact scalars.
    @Test(arguments: titles, noteForms)
    func eachTitleWithEachNoteFormRoundTripsByteForByte(title: String, note: String) async throws {
        let original = try Qualification.canonical(title: title, members: note)
        let trip = try await Qualification.roundTrip(original)
        #expect(trip.first == original)
        #expect(trip.second == original)
        let document = try LabDocument(decoding: trip.second)
        #expect(document.title.unicodeScalars.elementsEqual(title.unicodeScalars))
    }

    static let emptyShapes: [String] = [
        #","fields":{},"provenance":{},"attachments":[],"extras":{}"#,
        #","provenance":{}"#,
        #","attachments":[]"#,
        #","extras":{}"#,
        #","fields":{"note":"","empty":"","nothing":null,"zero":0,"none":[],"blank":{}},"extras":{"a":"","b":null,"c":[],"d":{},"e":false,"f":0.0}"#,
        #","x-empty":"","x-null":null,"x-list":[],"x-object":{},"x-false":false"#,
        #","provenance":{"origin":"","sourceID":null},"extras":{"nested":{"deeper":{"empty":{}}}}"#,
    ]

    /// Empty and absent optional members, known and unknown, at every level: each keeps its own
    /// form (`{}`, `[]`, `""`, `null`, `false`, `0`, `0.0`, or absent).
    @Test(arguments: emptyShapes)
    func emptyAndAbsentOptionalMembersKeepTheirForm(members: String) async throws {
        let original = try Qualification.canonical(title: "Empty shapes", members: members)
        let trip = try await Qualification.roundTrip(original)
        #expect(trip.first == original)
        #expect(trip.second == original)
    }

    /// Keys this build does not know keep their exact scalars, and their order is the canonical
    /// one (UTF-8 bytes), including a decomposed key and one outside the Basic Multilingual Plane.
    @Test func unicodeKeysOfUnknownFieldsKeepTheirScalars() async throws {
        let members = #","x-ключ":1,"🔑":"v","cre\u0300me":true,"extras":{"é":1,"e\u0301x":2,"釉":[]}"#
        let original = try Qualification.canonical(title: "Keys", members: members)
        let trip = try await Qualification.roundTrip(original)
        #expect(trip.second == original)
        let root = try LabDocument(decoding: trip.second).root
        let keys = root.keys.map { Array($0.unicodeScalars) }
        #expect(keys.contains(Array("cre\u{300}me".unicodeScalars)))
        #expect(!keys.contains(Array("cr\u{E8}me".unicodeScalars)))
        let text = String(decoding: trip.second, as: UTF8.self)
        let order = ["\"cre\u{300}me\"", "\"x-ключ\"", "\"🔑\""].map { text.range(of: $0)?.lowerBound }
        #expect(order.allSatisfy { $0 != nil })
        #expect(order.compactMap(\.self) == order.compactMap(\.self).sorted())
    }

    /// Two objects whose titles differ only by Unicode normalization stay two objects, each with
    /// its own bytes. The lab never normalizes one into the other.
    @Test func canonicallyEquivalentTitlesStayDistinctObjects() async throws {
        let lab = try await TestLab.make()
        let composed = try Qualification.canonical(title: "cr\u{E8}me")
        let decomposed = try Qualification.canonical(title: "cre\u{300}me")
        try await lab.importCreating(composed)
        try await lab.importCreating(decomposed)
        #expect(try await lab.export(LabDocument(decoding: composed).itemID) == composed)
        #expect(try await lab.export(LabDocument(decoding: decomposed).itemID) == decomposed)
        #expect(composed != decomposed)
    }

    /// Recorded behavior, not a round trip: a document whose title differs from the lab's copy only
    /// by normalization is treated as the same content (Swift compares strings by canonical
    /// equivalence). The review says it is already here, and the lab keeps its own scalars.
    @Test func aNormalizationOnlyChangeToAStoredTitleIsAlreadyPresent() async throws {
        let lab = try await TestLab.make()
        let id = UUID()
        let composed = try Qualification.canonical(id: id, title: "cr\u{E8}me")
        try await lab.importCreating(composed)
        let review = try await lab.importer.review(data: try Qualification.canonical(id: id, title: "cre\u{300}me"))
        #expect(Qualification.kind(review.plan) == "already-present")
        await lab.importer.discard(review.id)
        #expect(try await lab.export(ItemID(rawValue: id)) == composed)
    }

    /// A document without `revision` gains the store's revision on export: the contract makes
    /// `revision` the exporting store's own. From then on the bytes are stable.
    @Test func aDocumentWithoutARevisionGainsTheStoresRevisionThenStaysStable() async throws {
        let id = UUID()
        let bare = try Qualification.canonical(id: id, title: "No revision", revision: nil, members: #","fields":{"note":""}"#)
        let withRevision = try Qualification.canonical(id: id, title: "No revision", revision: 1, members: #","fields":{"note":""}"#)
        let trip = try await Qualification.roundTrip(bare)
        #expect(trip.first == withRevision)
        #expect(trip.second == withRevision)
        #expect(bare != withRevision)
    }

    /// A document written with other spacing, member order, and escapes comes back in canonical
    /// form, and its canonical digest, the import's identity, is unchanged.
    @Test func aNonCanonicalDocumentComesBackCanonicalWithTheSameDigest() async throws {
        let id = UUID()
        let raw = Data("""
        {  "title" : "cr\\u00e8me \\ud83e\\uddea",
           "kind":"collection-item",   "fields": {"note":"a\\tb"},
           "documentID":"\(id.uuidString)", "schemaVersion":1, "format":"native-lab-object", "revision":1 }
        """.utf8)
        let canonical = try LabDocument(decoding: raw)
        let trip = try await Qualification.roundTrip(raw)
        #expect(trip.first == canonical.encoded())
        #expect(trip.second == canonical.encoded())
        #expect(trip.first != raw)
        #expect(ContentDigest.sha256(trip.second) == canonical.digest)
    }
}

// MARK: - Criterion 2: A path-traversal attachment is rejected

@Suite struct TraversalAttachmentQualification {
    /// Attachment paths as JSON source text, so `\u002e` and `\\` reach the reader as escapes.
    static let unsafePaths: [(String, PathRejection)] = [
        ("../escape.txt", .parentReference),
        ("assets/../../escape.txt", .parentReference),
        ("assets/..", .parentReference),
        ("..", .parentReference),
        (#"\u002e\u002e/escape.txt"#, .parentReference),
        ("/etc/hosts", .absolute),
        ("C:/Windows/win.ini", .absolute),
        (#"..\\escape.txt"#, .backslash),
        ("assets\u{FF0F}..\u{FF0F}escape.txt", .lookalikeSeparator),
        ("assets\u{2215}..\u{2215}escape.txt", .lookalikeSeparator),
        ("\u{FF0E}\u{FF0E}/escape.txt", .lookalikeDot),
        ("\u{2025}/escape.txt", .lookalikeDot),
        ("./escape.txt", .currentReference),
        ("assets//escape.txt", .emptyComponent),
        ("assets/\u{202E}txt.exe", .bidiControl),
        ("assets/\u{200B}../escape.txt", .invisibleCharacter),
    ]

    static func document(attachments: String, id: UUID = UUID(), title: String = "Attachment probe") -> Data {
        Qualification.raw(id: id, title: title, members: #","attachments":\#(attachments)"#)
    }

    static func attachment(_ path: String) -> String {
        #"{"path":"\#(path)","byteCount":3,"sha256":"\#(Qualification.digest)"}"#
    }

    /// Each unsafe path is refused by name, from bytes in memory (a drop) and from a file (the file
    /// picker), before anything is planned. Nothing stays in staging, and the store is unchanged.
    @Test(arguments: unsafePaths)
    func anUnsafeAttachmentPathIsRefusedFromDataAndFromAFile(path: String, rejection: PathRejection) async throws {
        let lab = try await TestLab.make()
        let before = await lab.snapshot()
        let data = Self.document(attachments: "[\(Self.attachment(path))]")
        let expected = PortableObjectError.unsafeAttachmentPath(position: 1, rejection)
        await #expect(throws: expected) { try await lab.importer.review(data: data) }
        let file = try Qualification.temporaryFile(data)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        await #expect(throws: expected) { try await lab.importer.review(fileAt: file) }
        #expect(expected.userMessage.hasSuffix("Nothing was imported."))
        #expect(await lab.waitingImports().isEmpty)
        #expect(await lab.snapshot() == before)
    }

    @Test func theUnsafeAttachmentIsNamedByItsPosition() async throws {
        let lab = try await TestLab.make()
        let data = Self.document(attachments: "[\(Self.attachment("assets/safe.png")),\(Self.attachment("assets/../../escape.txt"))]")
        await #expect(throws: PortableObjectError.unsafeAttachmentPath(position: 2, .parentReference)) {
            try await lab.importer.review(data: data)
        }
        #expect(await lab.waitingImports().isEmpty)
    }

    /// An object the lab already holds, sent back with a new title and an unsafe attachment: the
    /// document is refused whole, and the stored copy is not changed.
    @Test func aTraversalOnAnObjectTheLabHoldsChangesNothing() async throws {
        let lab = try await TestLab.make()
        try await lab.importCreating(try Fixture.sample)
        let stored = try #require(await lab.item(Fixture.sampleID))
        let data = try Fixture.edited { root in
            root["title"] = .string("Replaced by a hostile copy")
            root["attachments"] = .array([.object([
                "path": .string("../../escape.txt"), "byteCount": .integer(3), "sha256": .string(Qualification.digest),
            ])])
        }
        await #expect(throws: PortableObjectError.unsafeAttachmentPath(position: 1, .parentReference)) {
            try await lab.importer.review(data: data)
        }
        #expect(await lab.item(Fixture.sampleID) == stored)
        #expect(await lab.waitingImports().isEmpty)
    }

    /// Only an attachment's `path` is ever read as a path. The same strings anywhere else are text,
    /// kept exactly and never used to reach a file.
    @Test func pathLikeTextOutsideAttachmentsIsOnlyText() async throws {
        let members = #","fields":{"note":"../../escape.txt","file":"..\\escape.txt"},"provenance":{"sourceID":"/etc/hosts"},"extras":{"path":"assets/../../escape.txt"}"#
        let original = try Qualification.canonical(title: "Paths as text", members: members)
        let trip = try await Qualification.roundTrip(original)
        #expect(trip.second == original)
    }

    /// Names that only look encoded or expandable (`%2e%2e`, `~`) are kept as literal names, and
    /// nothing decodes them into a traversal. The import is still refused, because this build
    /// stores no attachments, and nothing is written.
    @Test(arguments: ["%2e%2e/escape.txt", "~/escape.txt", "assets/..escape.txt"])
    func literalLookalikeNamesAreKeptAsNamesAndTheImportIsStillRefused(path: String) async throws {
        let lab = try await TestLab.make(path)
        let before = await lab.snapshot()
        let data = Self.document(attachments: "[\(Self.attachment(path))]")
        let document = try LabDocument(decoding: data)
        #expect(document.attachments.map(\.path.value) == [path])
        let review = try await lab.importer.review(data: data)
        #expect(review.plan == .refused(.attachmentsNotSupported(count: 1), stored: nil))
        await #expect(throws: PortableObjectError.attachmentsNotSupported(count: 1)) {
            try await lab.importer.commit(review, into: lab.inbox)
        }
        await lab.importer.discard(review.id)
        #expect(await lab.snapshot() == before)
    }

    /// The stored hostile fixture, pinned by hash, refused through a file as the picker reads it.
    @Test func theStoredTraversalFixtureIsRefused() async throws {
        let data = try Fixture.data("traversal-attachment.anlab")
        #expect(Qualification.sha256(data) == Qualification.traversalFixtureSHA256)
        let lab = try await TestLab.make()
        let before = await lab.snapshot()
        await #expect(throws: PortableObjectError.unsafeAttachmentPath(position: 1, .parentReference)) {
            try await lab.importer.review(fileAt: Fixture.folder.appending(path: "traversal-attachment.anlab"))
        }
        #expect(await lab.snapshot() == before)
        #expect(await lab.waitingImports().isEmpty)
    }
}

// MARK: - Criterion 3: Reimporting one document does not duplicate stable items

@Suite struct ReimportQualification {
    /// The same document five more times, from memory and from a file: one item, one receipt.
    @Test func manyReimportsFromEveryPathLeaveOneItem() async throws {
        let lab = try await TestLab.make()
        let sample = try Fixture.sample
        let first = try await lab.importCreating(sample)
        let after = await lab.snapshot()
        let file = try Qualification.temporaryFile(sample)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        for round in 0..<5 {
            let review = round.isMultiple(of: 2)
                ? try await lab.importer.review(data: sample)
                : try await lab.importer.review(fileAt: file)
            #expect(Qualification.kind(review.plan) == "already-present")
            await #expect(throws: PortableObjectError.nothingToImport) { try await lab.importer.commit(review, into: lab.inbox) }
            await lab.importer.discard(review.id)
        }
        #expect(await lab.snapshot() == after)
        #expect(await lab.count(Fixture.sampleID) == 1)
        #expect(await lab.store.receipt(for: first.receipt.requestID) == first.receipt)
        #expect(await lab.waitingImports().isEmpty)
    }

    /// The same object written differently (spacing, order, escapes) is the same object.
    @Test func aDifferentlyWrittenCopyIsTheSameObject() async throws {
        let lab = try await TestLab.make()
        try await lab.importCreating(try Fixture.sample)
        let sample = try LabDocument(decoding: try Fixture.sample)
        let rewritten = Data(PortableValue.object(sample.root).compactText().utf8)
        #expect(rewritten != (try Fixture.sample))
        let review = try await lab.importer.review(data: rewritten)
        #expect(review.digest == sample.digest)
        #expect(Qualification.kind(review.plan) == "already-present")
        await lab.importer.discard(review.id)
        #expect(await lab.count(Fixture.sampleID) == 1)
    }

    /// Two reviews of one new object, both committed to the same collection: the second is a
    /// retry and gets the first receipt back. One item.
    @Test func twoReviewsCommittedToOneCollectionCommitOnce() async throws {
        let lab = try await TestLab.make()
        let first = try await lab.importer.review(data: try Fixture.sample)
        let second = try await lab.importer.review(data: try Fixture.sample)
        let created = try await lab.importer.commit(first, into: lab.inbox)
        let retried = try await lab.importer.commit(second, into: lab.inbox)
        #expect(!created.isReplay && retried.isReplay)
        #expect(retried.receipt == created.receipt)
        #expect(await lab.count(Fixture.sampleID) == 1)
        #expect(await lab.waitingImports().isEmpty)
    }

    /// Two reviews of one new object committed to different collections: the second is refused and
    /// one item stays where the first put it.
    ///
    /// Staging names a staged copy by its content, so both reviews share one copy, and the first
    /// commit removes it. The second commit is therefore refused as no longer waiting
    /// (`staging/not-found`) before it could be refused as stale.
    @Test func twoReviewsCommittedToTwoCollectionsCommitOnce() async throws {
        let lab = try await TestLab.make()
        let first = try await lab.importer.review(data: try Fixture.sample)
        let second = try await lab.importer.review(data: try Fixture.sample)
        #expect(first.id == second.id, "one staged copy per content")
        _ = try await lab.importer.commit(first, into: lab.inbox)
        let after = await lab.snapshot()
        await #expect(throws: PortableObjectError.staging(.notFound)) { try await lab.importer.commit(second, into: lab.shelf) }
        #expect(await lab.snapshot() == after)
        #expect(try #require(await lab.item(Fixture.sampleID)).collectionID == lab.inbox)
        #expect(await lab.count(Fixture.sampleID) == 1)
    }

    /// Finding for the module owner, recorded as current behavior: because two reviews of the same
    /// bytes share one staged copy, closing one review (another window's Close) withdraws the other.
    /// Its commit is refused with "This import is no longer waiting…", and nothing is written. Safe,
    /// but the person must import again.
    @Test func closingOneOfTwoIdenticalReviewsWithdrawsTheOther() async throws {
        let lab = try await TestLab.make()
        let before = await lab.snapshot()
        let kept = try await lab.importer.review(data: try Fixture.sample)
        let closed = try await lab.importer.review(data: try Fixture.sample)
        await lab.importer.discard(closed.id)
        await #expect(throws: PortableObjectError.staging(.notFound)) { try await lab.importer.commit(kept, into: lab.inbox) }
        #expect(PortableObjectError.staging(.notFound).userMessage.hasPrefix("This import is no longer waiting."))
        #expect(await lab.snapshot() == before)
        #expect(await lab.waitingImports().isEmpty)
    }

    /// Identity decides, never a title: another object with the same title is a second item, and
    /// the first is not overwritten.
    @Test func theSameTitleUnderAnotherIdentityIsAnotherObject() async throws {
        let lab = try await TestLab.make()
        let a = try Qualification.canonical(title: "Twin title", members: #","fields":{"note":"first"}"#)
        let b = try Qualification.canonical(title: "Twin title", members: #","fields":{"note":"second"}"#)
        try await lab.importCreating(a)
        let review = try await lab.importer.review(data: b)
        #expect(Qualification.kind(review.plan) == "create")
        _ = try await lab.importer.commit(review, into: lab.inbox)
        #expect(try await lab.export(LabDocument(decoding: a).itemID) == a)
        #expect(try await lab.export(LabDocument(decoding: b).itemID) == b)
    }

    /// A changed copy updates the one item when the person applies it, and the original bytes sent
    /// again are a difference to review, never a second item.
    @Test func aChangedCopyAndTheOriginalAgainNeverMakeASecondItem() async throws {
        let lab = try await TestLab.make()
        let sample = try Fixture.sample
        try await lab.importCreating(sample)
        let changed = try Fixture.edited { $0["title"] = .string("Glaze test, refired") }
        let apply = try await lab.importer.review(data: changed)
        #expect(Qualification.kind(apply.plan) == "differs")
        #expect(try await lab.importer.commit(apply).change == .updated)
        let back = try await lab.importer.review(data: sample)
        #expect(Qualification.kind(back.plan) == "differs")
        await lab.importer.discard(back.id)
        #expect(await lab.count(Fixture.sampleID) == 1)
    }

    /// An object that went to another lab and came back is recognized, even though the other lab
    /// exported it at its own revision.
    @Test func anObjectBackFromAnotherLabIsRecognized() async throws {
        let home = try await TestLab.make("home")
        let id = ItemID()
        try await home.perform(.createItem(draft: ItemDraft(id: id, in: home.inbox, title: EntityTitle("Travelling"), note: ItemNote("v1"))))
        try await home.perform(.updateItem(id: id, expected: .initial, changes: ItemChanges(note: ItemNote("v2"))))
        let away = try await TestLab.make("away")
        try await away.importCreating(try await home.export(id))
        let returned = try await away.export(id)
        #expect(try LabDocument(decoding: returned).revision == 1)
        let review = try await home.importer.review(data: returned)
        #expect(Qualification.kind(review.plan) == "already-present")
        await home.importer.discard(review.id)
        #expect(await home.count(id) == 1)
    }
}

// MARK: - Step 3: denial, cancellation, stale and duplicate state, and reset

@Suite struct ImportBoundaryQualification {
    /// An importer for `lab` that acts as `actor`, with its own staging folder.
    private func importer(for lab: TestLab, as actor: ActorScope) throws -> PortableObjectsImporter {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PortableObjectsQualification-\(UUID().uuidString)", directoryHint: .isDirectory)
        return try PortableObjectsImporter(backend: ServiceBackend(service: lab.service, actor: actor), stagingRoot: root)
    }

    /// Denial: an actor that may read but not commit (a model tool, or the app UI without the
    /// commit permission) can review but not import. Nothing is written and no receipt is kept;
    /// the app UI then imports the same bytes once.
    @Test(arguments: [
        ActorScope(adapter: .modelTool, grants: Set(Permission.allCases)),
        ActorScope(adapter: .appUI, grants: [.read, .propose]),
    ])
    func anActorWithoutTheCommitPermissionCannotImport(actor: ActorScope) async throws {
        let lab = try await TestLab.make()
        let denied = try importer(for: lab, as: actor)
        let before = await lab.snapshot()
        let review = try await denied.review(data: try Fixture.sample)
        #expect(Qualification.kind(review.plan) == "create")
        await #expect(throws: PortableObjectError.notAuthorized) { try await denied.commit(review, into: lab.inbox) }
        #expect(await lab.snapshot() == before)
        #expect(await lab.store.receipt(for: ImportRequest.create(review.digest, into: lab.inbox)) == nil)
        await denied.discard(review.id)

        let result = try await lab.importCreating(try Fixture.sample)
        #expect(result.change == .created && !result.isReplay)
        #expect(await lab.count(Fixture.sampleID) == 1)
    }

    /// Declining: closing the review removes the staged copy, and that review can no longer commit.
    @Test func aClosedReviewCanNoLongerCommit() async throws {
        let lab = try await TestLab.make()
        let before = await lab.snapshot()
        let review = try await lab.importer.review(data: try Fixture.sample)
        await lab.importer.discard(review.id)
        #expect(await lab.waitingImports().isEmpty)
        await #expect(throws: PortableObjectError.self) { try await lab.importer.commit(review, into: lab.inbox) }
        #expect(await lab.snapshot() == before)
    }

    /// Cancellation, then a retry of the same review: it commits exactly once, and a third attempt
    /// replays the receipt.
    @Test func aCancelledCommitCanBeRetriedAndCommitsOnce() async throws {
        let lab = try await TestLab.make()
        let review = try await lab.importer.review(data: try Fixture.sample)
        let before = await lab.snapshot()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await lab.importer.commit(review, into: lab.inbox)
        }
        await #expect(throws: PortableObjectError.cancelled) { try await cancelled.value }
        #expect(await lab.snapshot() == before)
        let committed = try await lab.importer.commit(review, into: lab.inbox)
        let again = try await lab.importer.commit(review, into: lab.inbox)
        #expect(!committed.isReplay && again.isReplay && again.receipt == committed.receipt)
        #expect(await lab.count(Fixture.sampleID) == 1)
    }

    /// Stale: the object appeared another way while the review was open. The reviewed creation no
    /// longer applies, so nothing is written over it.
    @Test func anObjectCreatedDuringTheReviewStopsTheCommit() async throws {
        let lab = try await TestLab.make()
        let review = try await lab.importer.review(data: try Fixture.sample)
        try await lab.perform(.createItem(draft: ItemDraft(
            id: Fixture.sampleID, in: lab.shelf, title: EntityTitle("Made meanwhile"), note: ItemNote("")
        )))
        let before = await lab.snapshot()
        await #expect(throws: PortableObjectError.stateChanged) { try await lab.importer.commit(review, into: lab.inbox) }
        #expect(await lab.snapshot() == before)
        #expect(try #require(await lab.item(Fixture.sampleID)).title.value == "Made meanwhile")
        #expect(await lab.count(Fixture.sampleID) == 1)
    }

    /// Stale: the stored copy was archived while a change to it was under review.
    @Test func aCopyArchivedDuringTheReviewIsNotChanged() async throws {
        let lab = try await TestLab.make()
        try await lab.importCreating(try Fixture.sample)
        let review = try await lab.importer.review(data: try Fixture.edited { $0["title"] = .string("Changed") })
        #expect(Qualification.kind(review.plan) == "differs")
        try await lab.perform(.archiveItem(id: Fixture.sampleID, expected: .initial))
        let before = await lab.snapshot()
        await #expect(throws: PortableObjectError.stateChanged) { try await lab.importer.commit(review) }
        #expect(await lab.snapshot() == before)
    }

    /// Reset Demo beside imported data: it restores the demo sample an import changed, and leaves
    /// the imported object exactly as it was, with its document.
    @Test func resetDemoLeavesImportedObjectsAndTheirDocumentsAlone() async throws {
        let lab = try await TestLab.make()
        let sample = try Fixture.sample
        try await lab.importCreating(sample)
        let imported = try #require(await lab.item(Fixture.sampleID))

        // An import that changes a demo sample: allowed, and Reset Demo's to undo.
        var demo = try LabDocument(decoding: try await lab.export(TestLab.demoItem)).root
        demo["title"] = .string("Amber, renamed by an import")
        let review = try await lab.importer.review(data: Data(PortableValue.object(demo).canonicalText(topLevelOrder: LabDocument.schemaFields).utf8))
        #expect(Qualification.kind(review.plan) == "differs")
        _ = try await lab.importer.commit(review)

        let reset = try await lab.resetDemo()
        #expect(reset.changes.map(\.entity) == [.item(TestLab.demoItem)])
        #expect(try #require(await lab.item(TestLab.demoItem)).title.value == "Amber")
        #expect(await lab.item(Fixture.sampleID) == imported)
        #expect(try await lab.export(Fixture.sampleID) == sample)
    }

    /// A review left open across Reset Demo still commits the reviewed object as your own, and a
    /// second Reset Demo does not touch it.
    @Test func aReviewOpenAcrossResetDemoStillImportsAsYourOwn() async throws {
        let lab = try await TestLab.make()
        let review = try await lab.importer.review(data: try Fixture.sample)
        try await lab.resetDemo()
        let result = try await lab.importer.commit(review, into: lab.inbox)
        #expect(result.change == .created)
        try await lab.resetDemo()
        #expect(try #require(await lab.item(Fixture.sampleID)).namespace == .user)
        #expect(try await lab.export(Fixture.sampleID) == (try Fixture.sample))
    }
}

// MARK: - Step 1: the complete fixture interaction, replayed from a clean state

@Suite struct PortableObjectsInteractionReplay {
    /// The interaction LAB-008 declares, from two clean labs: import the sample, export it, import
    /// the export into a second lab, export again, reimport it three ways, apply a changed copy and
    /// undo it, refuse the hostile fixtures, and Reset Demo. Returns one line per observation, with
    /// no random identifier in any of them, so two replays can be compared line for line.
    static func replay() async throws -> [String] {
        var lines: [String] = []
        let sample = try Fixture.sample
        lines.append("sample sha256:\(Qualification.sha256(sample))")

        let first = try await TestLab.make("replay-first")
        let review = try await first.importer.review(data: sample)
        lines.append("first lab review: \(Qualification.kind(review.plan))")
        let created = try await first.importer.commit(review, into: first.inbox)
        lines.append("first lab import: \(created.receipt.admitted.operation.kind.rawValue), \(created.receipt.status), \(created.receipt.admitted.adapter.rawValue)")
        let exported = try await first.export(Fixture.sampleID)
        lines.append("first lab export sha256:\(Qualification.sha256(exported))")

        let second = try await TestLab.make("replay-second")
        let file = try Qualification.temporaryFile(exported)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let fromFile = try await second.importer.review(fileAt: file)
        lines.append("second lab review from a file: \(Qualification.kind(fromFile.plan))")
        _ = try await second.importer.commit(fromFile, into: second.inbox)
        let reexported = try await second.export(Fixture.sampleID)
        lines.append("second lab export sha256:\(Qualification.sha256(reexported))")

        for (path, data) in [("data", reexported), ("file", nil), ("sample", sample)] as [(String, Data?)] {
            let again = if let data { try await second.importer.review(data: data) } else { try await second.importer.review(fileAt: file) }
            lines.append("reimport from \(path): \(Qualification.kind(again.plan))")
            await second.importer.discard(again.id)
        }
        lines.append("items with the sample's ID: \(await second.count(Fixture.sampleID))")

        let changed = try await second.importer.review(data: try Fixture.edited { $0["title"] = .string("Glaze test, refired") })
        lines.append("changed copy: \(Qualification.kind(changed.plan))")
        let applied = try await second.importer.commit(changed)
        lines.append("apply: \(applied.receipt.admitted.operation.kind.rawValue), undo offered: \(applied.receipt.undo != nil)")
        let undo = try #require(applied.receipt.undo)
        let undone = try await second.perform(undo)
        lines.append("undo: \(undone.status)")
        let afterUndo = try LabDocument(decoding: try await second.export(Fixture.sampleID))
        var expected = try LabDocument(decoding: sample).root
        expected["revision"] = .integer(3)
        lines.append("export after undo: revision \(afterUndo.revision ?? 0), other members equal: \(afterUndo.root == expected)")

        for name in ["traversal-attachment.anlab", "malformed.anlab", "newer-schema.anlab", "authority-field.anlab", "duplicate-keys.anlab"] {
            let hostile = try Fixture.data(name)
            do throws(PortableObjectError) {
                _ = try await second.importer.review(data: hostile)
                lines.append("\(name): imported")
            } catch {
                lines.append("\(name): refused \(error.code)")
            }
        }
        lines.append("staging after refusals: \(await second.waitingImports().count)")

        let reset = try await second.resetDemo()
        lines.append("reset changed: \(reset.changes.map { $0.entity == .item(TestLab.demoItem) ? "demo item" : "other" })")
        lines.append("imported object after reset: \(await second.item(Fixture.sampleID)?.namespace.rawValue ?? "missing"), revision \(await second.item(Fixture.sampleID)?.revision.rawValue ?? 0)")
        return lines
    }

    @Test func theInteractionReplaysIdenticallyFromCleanLabs() async throws {
        let first = try await Self.replay()
        let second = try await Self.replay()
        #expect(first == second)
        let sampleHash = "sha256:\(Qualification.sha256(try Fixture.sample))"
        #expect(first.contains("first lab export \(sampleHash)"))
        #expect(first.contains("second lab export \(sampleHash)"))
        #expect(first.contains("reimport from data: already-present"))
        #expect(first.contains("reimport from file: already-present"))
        #expect(first.contains("reimport from sample: already-present"))
        #expect(first.contains("items with the sample's ID: 1"))
        #expect(first.contains("export after undo: revision 3, other members equal: true"))
        #expect(first.contains("traversal-attachment.anlab: refused unsafe-attachment-path/parent-reference"))
        #expect(first.contains("staging after refusals: 0"))
        #expect(first.contains("imported object after reset: user, revision 3"))
    }
}
