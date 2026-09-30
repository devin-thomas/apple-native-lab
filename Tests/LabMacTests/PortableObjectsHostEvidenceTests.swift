import AppKit
import CoreTransferable
import CryptoKit
import Foundation
import LabDomain
import LabStore
import LabSupport
import PortableObjects
import Testing
import UniformTypeIdentifiers
@testable import NativeLab

/// LAB-008-B step 1 with its evidence: the complete Portable Objects fixture interaction in the
/// sandboxed Mac app, from clean state, through the host's own `PortableObjectsSession`,
/// `LabLibrary`, and two fresh SQLite stores. The export's bytes and the object's stable ID are
/// the claims: export from one store, import the file into the other, export again, and compare.
///
/// The test attaches an `EvidenceRecord` of what it observed, with the toolchain read from this
/// app bundle. To keep it, run the test with a result bundle and export the attachment:
///
///     xcodebuild … -scheme LabMac-Core -only-testing:LabMacTests/PortableObjectsHostEvidenceTests \
///       -resultBundlePath <bundle> LAB_SOURCE_REVISION=<sha> test
///     xcrun xcresulttool export attachments --path <bundle> --output-path <folder>
@MainActor
@Suite struct PortableObjectsHostEvidenceTests {
    static let check = "Portable Objects round trip in the Mac host: export, import into a second store, export again, byte-identical under one stable ID; reimports, a traversal attachment, and Reset Demo"

    @Test func theInteractionRoundTripsByteForByteUnderOneStableID() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PortableObjectsHostEvidenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let started = Date()
        let sample = try #require(PortableSample.data)

        var observations: [String] = []
        var differences: [String] = []
        func check(_ same: Bool, _ what: String) {
            #expect(same, "\(what)")
            if same { observations.append(what) } else { differences.append(what) }
        }

        // 1. Store A: the host's first run seeds the demo; the person has one collection.
        let a = try await PortableHostLab.make("a", in: folder)
        await a.session.openSample(library: a.library)
        check(a.plan == "create", "the sample reviews as new to store A")
        let created = try #require(await a.session.commit(library: a.library))
        check(created.receipt.status == .committed && created.receipt.admitted.adapter == .appUI
              && created.receipt.admitted.operation.kind == .createItem,
              "store A commits one createItem as the app UI")

        // 2. Export from A, as data (a drag or share) and as a file (the save panel, Finder).
        let object = try #require(a.session.exportPreview(for: PortableHostLab.sampleID)).object
        check(object.data == sample, "store A exports the sample's exact bytes")
        let exportedFile = try await object.export(to: folder, contentType: .labObject)
        check(try Data(contentsOf: exportedFile) == sample, "the exported file holds the same bytes")

        // 3. Store B imports that file and exports it again.
        let b = try await PortableHostLab.make("b", in: folder)
        await b.session.open(fileAt: exportedFile, library: b.library)
        check(b.plan == "create" && b.session.review?.document.itemID == PortableHostLab.sampleID,
              "the file reviews as new to store B under the sample's stable ID")
        let imported = try #require(await b.session.commit(library: b.library))
        check(imported.receipt.affectedEntities == [.item(PortableHostLab.sampleID)], "store B's receipt names the stable ID")
        check(try #require(b.session.exportPreview(for: PortableHostLab.sampleID)).object.data == sample,
              "store B exports the same bytes")

        // 4. Reimports into B, three ways: nothing added, no new receipt.
        let receiptsB = b.library.receipts.count
        await b.session.open(fileAt: exportedFile, library: b.library)
        check(b.plan == "already-present", "reimporting the file: already in this lab")
        check(await b.session.commit(library: b.library) == nil, "committing the reimport does nothing")
        await b.session.receive([try await PortableHostLab.dropped(object)], library: b.library)
        check(b.plan == "already-present", "a drop of the object: already in this lab")
        await b.session.openSample(library: b.library)
        check(b.plan == "already-present", "the bundled sample: already in this lab")
        await b.session.closeReview()
        check(b.library.receipts.count == receiptsB, "no reimport adds a receipt")

        // 5. Unicode and empty optional fields through both stores.
        for (name, bytes) in try PortableHostLab.variants() {
            let file = folder.appending(path: "variant-\(name).anlab")
            try bytes.write(to: file)
            await a.session.open(fileAt: file, library: a.library)
            _ = await a.session.commit(library: a.library)
            let id = try LabDocument(decoding: bytes).itemID
            let fromA = try #require(a.session.exportPreview(for: id)).object
            await b.session.receive([try await PortableHostLab.dropped(fromA)], library: b.library)
            _ = await b.session.commit(library: b.library)
            check(fromA.data == bytes && b.session.exportPreview(for: id)?.object.data == bytes,
                  "variant \(name) is byte-identical through both stores")
        }

        // 6. The traversal fixture, by file and by drop: refused, nothing staged or stored.
        let hostile = PortableHostLab.traversalFixture
        check(PortableHostLab.sha256(hostile) == PortableHostLab.traversalFixtureSHA256, "the traversal document is the stored fixture")
        let hostileFile = folder.appending(path: "traversal-attachment.anlab")
        try hostile.write(to: hostileFile)
        let receiptsBeforeHostile = b.library.receipts.count
        await b.session.open(fileAt: hostileFile, library: b.library)
        check(b.session.review == nil && b.session.message?.hasPrefix("Attachment 1 has a path that points outside the object") == true,
              "the traversal file is refused with its sentence")
        // A successful review clears the message, so the drop's refusal is its own.
        await b.session.openSample(library: b.library)
        await b.session.closeReview()
        check(b.session.message == nil, "a successful review clears the refusal")
        await b.session.receive([try await PortableHostLab.droppedJSON(hostile)], library: b.library)
        check(b.session.review == nil && b.session.message?.hasPrefix("Attachment 1 has a path that points outside the object") == true,
              "the traversal drop is refused with its sentence")
        check(b.library.receipts.count == receiptsBeforeHostile && b.pendingStaged() == 0,
              "the refusals left no receipt and nothing in staging")

        // 7. Reset Demo in B: the imported object and its document are untouched.
        let before = try #require(b.session.entry(PortableHostLab.sampleID)?.item)
        let reset = try #require(await b.library.resetDemo())
        check(reset.receipt.status == .committed, "Reset Demo commits")
        await b.session.load(b.library)
        check(b.session.entry(PortableHostLab.sampleID)?.item == before, "the imported object is unchanged by Reset Demo")
        check(b.session.exportPreview(for: PortableHostLab.sampleID)?.object.data == sample, "and still exports the same bytes")

        // 8. Read store B directly: one item under the stable ID.
        let store = try await SQLiteOperationStore(url: b.storeURL)
        let items = try await store.items(in: nil)
        check(items.filter { $0.id == PortableHostLab.sampleID }.count == 1, "store B holds one item under the sample's ID")
        check(try await store.receipt(for: imported.receipt.requestID)?.status == .committed, "store B holds the import's receipt")
        let userItems = items.filter { $0.namespace == .user }.count
        let demoItems = items.filter { $0.namespace == .demo }.count
        check(userItems == 1 + PortableHostLab.variantCount, "store B holds the sample and the \(PortableHostLab.variantCount) variants as its own")

        let seedBytes = try Data(contentsOf: try #require(Bundle.main.url(forResource: "seed", withExtension: "json")))
        let record = try EvidenceRecord(
            subject: "LAB-008",
            check: Self.check,
            date: started,
            provenance: .current,
            execution: .fixture,
            inputs: [
                "sample:app-bundle@sha256:\(PortableHostLab.sha256(sample))",
                "traversal:Fixtures/LAB-008/traversal-attachment.anlab@sha256:\(PortableHostLab.sha256(hostile))",
                "seed:app-bundle@sha256:\(PortableHostLab.sha256(seedBytes))",
            ] + (try PortableHostLab.variants()).map { "variant:\($0.0)@sha256:\(PortableHostLab.sha256($0.1))" },
            steps: [
                "xcodebuild -scheme LabMac-Core -only-testing:LabMacTests/PortableObjectsHostEvidenceTests test",
                "Stores A and B: fresh SQLite stores in the app container, each seeded by the host's first run (Reset Demo), each with one collection of the person's own",
                "A: Import Sample Object, then Import (PortableObjectsSession, as the app UI)",
                "A: the export preview's object, as data and written by the Transferable file export",
                "B: Import from File… with that file, then Import; B's export preview",
                "B: the same file again, a drop of A's object, and Import Sample Object: each reviewed, and committing does nothing",
                "5 Unicode and empty-field variants: imported into A by file, dropped from A into B, exported from both",
                "B: the traversal fixture by file and by drop",
                "B: Reset Demo, then the export preview again; store B read directly",
            ],
            outcome: differences.isEmpty
                ? .passed(observed: "All \(observations.count) checks matched. The sample (682 bytes) exported from store A with its exact bytes, as data and as a file; store B imported the file under the stable ID F1586771-0F15-4044-A372-5F9BC9968FDB and exported the same bytes. Reimporting by file, by drop, and from the bundle each reviewed as already in the lab, committed nothing, and added no receipt. 5 Unicode and empty-field variants were byte-identical through both stores. The traversal fixture was refused by file and by drop with its sentence, leaving no receipt and nothing in staging. Reset Demo left the imported object and its bytes unchanged. Store B held one item under the stable ID, \(userItems) items of the person's own, and \(demoItems) demo items.")
                : .failed(observed: "\(differences.count) of \(observations.count + differences.count) checks failed: " + differences.joined(separator: "; ") + "."),
            limitations: [
                "Fixture path: hosted tests in the sandboxed Mac app on the development Mac, on fresh stores in the app container. It supports implemented at most.",
                "Drags and drops are the item-provider transfers a drag carries, run in process. No window, pointer, Finder, or save panel took part; the file was written by the Transferable file export the save panel uses.",
                "No physical iPhone or iPad and no iOS simulator ran in this check.",
            ]
        )
        Attachment.record(try Self.json(record), named: "LAB-008-portable-objects-host-round-trip.json")
        #expect(record.result == .passed)
        #expect(record.provenance.xcodeBuild != "unknown" && record.provenance.sdkName.hasPrefix("macosx"))
        #expect(record.supportedState == .implemented)
    }

    private static func json(_ record: EvidenceRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
    }
}

/// One started library on its own SQLite store and staging folder, with one collection of the
/// person's own, and its Portable Objects session.
@MainActor
struct PortableHostLab {
    static let sampleID = ItemID(rawValue: UUID(uuidString: "F1586771-0F15-4044-A372-5F9BC9968FDB")!)

    let library: LabLibrary
    let session: PortableObjectsSession
    let storeURL: URL
    let stagingRoot: URL
    let collection: CollectionID

    /// - Parameter staging: A staging folder to share with another session, as the app's windows
    ///   share one; by default the lab has its own.
    static func make(_ name: String, in folder: URL, staging shared: URL? = nil) async throws -> PortableHostLab {
        let directory = folder.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        let collection = CollectionID()
        _ = try await library.submit(
            .createCollection(draft: CollectionDraft(id: collection, title: EntityTitle("Imports"))),
            requestID: RequestID(), authority: .userAction, names: [:]
        )
        let staging = shared ?? directory.appending(path: "staging", directoryHint: .isDirectory)
        let session = PortableObjectsSession(locateStaging: { staging })
        await session.load(library)
        try #require(session.destinationID == collection)
        return PortableHostLab(library: library, session: session, storeURL: url, stagingRoot: staging, collection: collection)
    }

    /// The review's plan, as a word.
    var plan: String {
        switch session.review?.plan {
        case .create?: "create"
        case .alreadyPresent?: "already-present"
        case .differs?: "differs"
        case .refused?: "refused"
        case nil: "none"
        }
    }

    /// Staged imports waiting in this lab's staging folder.
    func pendingStaged() -> Int {
        let pending = stagingRoot.appending(path: "pending", directoryHint: .isDirectory)
        return ((try? FileManager.default.contentsOfDirectory(atPath: pending.path(percentEncoded: false))) ?? []).count
    }

    /// The object as a drop delivers it: registered with an item provider, loaded as incoming.
    static func dropped(_ object: PortableObject) async throws -> IncomingObject {
        let provider = NSItemProvider()
        provider.register(object)
        return try await load(provider)
    }

    /// Bytes another app drops as JSON.
    static func droppedJSON(_ data: Data) async throws -> IncomingObject {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.json.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return try await load(provider)
    }

    private static func load(_ provider: NSItemProvider) async throws -> IncomingObject {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: IncomingObject.self) { continuation.resume(with: $0) }
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Inputs

    /// SHA-256 of `Fixtures/LAB-008/traversal-attachment.anlab`, pinned in the package's
    /// `TraversalAttachmentQualification` too. The sandboxed app cannot read the repository, so it
    /// carries a copy of the fixture's exact bytes.
    static let traversalFixtureSHA256 = "49905ccd9317ff9c381533953a7735e20d82e4783e76a6ba52c830ffa7cf591a"

    static let traversalFixture = Data("""
    {
      "format": "native-lab-object",
      "schemaVersion": 1,
      "documentID": "C4C12097-60B1-4FF8-B68F-A74C5BF80590",
      "kind": "collection-item",
      "revision": 1,
      "title": "Harmless-looking swatch",
      "fields": {
        "note": "Its attachment path climbs out of the object's folder."
      },
      "attachments": [
        {
          "byteCount": 17,
          "mediaType": "text/plain",
          "path": "assets/../../../Library/Preferences/secrets.plist",
          "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
        }
      ],
      "extras": {}
    }

    """.utf8)

    static let variantCount = 5

    /// Canonical documents with fixed IDs: decomposed and precomposed accents, a ZWJ sequence,
    /// right-to-left and CJK text, each form of an empty note, empty containers, and Unicode keys.
    static func variants() throws -> [(String, Data)] {
        let cases: [(String, String, String, String)] = [
            ("decomposed-empty-note", "9B0F4C1E-2D1A-4F4B-8B8E-1A0C5E7D2F01", "cre\u{300}me bru\u{302}le\u{301}e",
             #","fields":{"note":""}"#),
            ("zwj-null-note", "9B0F4C1E-2D1A-4F4B-8B8E-1A0C5E7D2F02", "👩🏽‍🔬 at the kiln 🧪", #","fields":{"note":null}"#),
            ("rtl-cjk-no-fields", "9B0F4C1E-2D1A-4F4B-8B8E-1A0C5E7D2F03", "釉薬の試し · שלום · مرحبا", ""),
            ("empty-containers", "9B0F4C1E-2D1A-4F4B-8B8E-1A0C5E7D2F04", "Empty shapes",
             #","fields":{"note":"","empty":"","nothing":null,"none":[],"blank":{}},"provenance":{},"attachments":[],"extras":{"a":"","b":null,"f":0.0},"x-false":false"#),
            ("unicode-keys", "9B0F4C1E-2D1A-4F4B-8B8E-1A0C5E7D2F05", "Ｆｕｌｌｗｉｄｔｈ keys",
             #","fields":{"note":"Zweite Zeile\nsecond\ttabbed"},"x-ключ":1,"🔑":"v","crème":true,"extras":{"é":1,"釉":[]}"#),
        ]
        return try cases.map { name, id, title, members in
            let raw = #"{"format":"native-lab-object","schemaVersion":1,"documentID":"\#(id)","kind":"collection-item","revision":1,"title":"\#(title)"\#(members)}"#
            return (name, try LabDocument(decoding: Data(raw.utf8)).encoded())
        }
    }
}
