import Foundation
import LabDomain
import LabStore
import LabSupport
import ShareIngress
import Testing
import UniformTypeIdentifiers
@testable import NativeLab

/// LAB-007-B step 1 with its evidence: the showcase interaction (`Fixtures/showcase/share-ingress/`)
/// in the sandboxed Mac app, from the intake to the receipt, once through the host's paste and
/// file-picker fallback and once through the share extension's folder, each on a fresh SQLite
/// store that the host's first run seeds. Both must commit exactly the script's additions and end
/// in the same state.
///
/// The share extension itself is not in the Mac build. Its side is played by `IngressStation` on a
/// second folder, the code the iOS extension runs, and the host reads that folder as it reads the
/// App Group folder in a SystemSurfaces build.
///
/// The test attaches an `EvidenceRecord` of what it observed, with the toolchain read from this
/// app bundle. To keep it, run the test with a result bundle and export the attachment:
///
///     xcodebuild … -scheme LabMac-Core -only-testing:LabMacTests/ShareIngressHostEvidenceTests \
///       -resultBundlePath <bundle> LAB_SOURCE_REVISION=<sha> test
///     xcrun xcresulttool export attachments --path <bundle> --output-path <folder>
@MainActor
@Suite struct ShareIngressHostEvidenceTests {
    static let check = "Share Ingress showcase interaction in the Mac host, from the intake to the receipt: the paste and file-picker fallback and the share extension's folder commit the same additions, each receipt naming its adapter"

    @Test func theInteractionRunsFromTheIntakeToTheReceiptThroughBothFolders() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShareIngressHostEvidenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let started = Date()
        let script = try HostShareIngress.Script.load()

        let pasted = try await HostShareIngress.run(.paste, script: script, in: folder.appending(path: "paste"))
        let shared = try await HostShareIngress.run(.shareSheet, script: script, in: folder.appending(path: "share"))

        var differences: [String] = []
        var comparisons = 0
        func compare(_ same: Bool, _ what: String) {
            comparisons += 1
            #expect(same, "\(what)")
            if !same { differences.append(what) }
        }

        // The refusals: each bad item by position, nothing kept, and the rest went on.
        compare(pasted.refusedPositions == [1, 2] && shared.refusedPositions == [1, 2], "hostile items refused by position")
        compare(pasted.leftAfterRefusal == 0 && shared.leftAfterRefusal == 0, "refused items kept nothing")

        // The intake, with its origins.
        compare(pasted.arrivals == [
            .init(surface: .paste, position: 1, count: 1, kind: "text"),
            .init(surface: .paste, position: 1, count: 1, kind: "link"),
            .init(surface: .filePicker, position: 1, count: 1, kind: "files"),
        ], "the paste fallback's intake")
        compare(shared.arrivals == [
            .init(surface: .shareExtension, position: 1, count: 4, kind: "link"),
            .init(surface: .shareExtension, position: 2, count: 4, kind: "text"),
            .init(surface: .shareExtension, position: 3, count: 4, kind: "files"),
            .init(surface: .shareExtension, position: 4, count: 4, kind: "files"),
        ], "the share's intake, in the share's order")
        compare(pasted.shareSheetStatus == .notInThisBuild && shared.shareSheetStatus == .available, "share sheet status")

        // The additions: exactly the script's, each naming the adapter its folder implies.
        for (run, adapter, title) in [(pasted, AdapterKind.appUI, "App UI"), (shared, .shareExtension, "Share extension")] {
            for addition in script.additions {
                let record = run.additions[addition.step]
                compare(record?.receipt.requestID == addition.request, "\(title) \(addition.step) request ID")
                compare(record?.receipt.admitted.operation == .createItem(draft: addition.draft), "\(title) \(addition.step) operation")
                compare(record?.receipt.admitted.adapter == adapter, "\(title) \(addition.step) receipt names \(title)")
                compare(record.map { ReceiptPresentation($0).adapter } == title, "\(title) \(addition.step) receipt reads \(title)")
                compare(record?.receipt.status == .committed, "\(title) \(addition.step) committed")
            }
            compare(run.duplicateWasRecognized, "\(title) adding the same note again returned its first receipt, listed once")
            compare(run.resetChanges == [.item(HostShareIngress.archivedSample)], "\(title) Reset Demo restored only the archived sample")
            compare(run.stillWaiting.allSatisfy { $0 == "files" }, "\(title) only files are still waiting")
        }
        compare(pasted.stillWaiting.count == 1 && shared.stillWaiting.count == 2, "waiting files")

        // The same persisted state, field for field.
        compare(pasted.collections == shared.collections, "collections")
        compare(pasted.items == shared.items, "items")
        compare(pasted.collections.count == 4 && pasted.items.count == 14, "4 collections and 14 items")
        let imported = pasted.items.filter { $0.namespace == .user }
        compare(imported.map(\.id).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
                == script.additions.map(\.draft.id).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }, "imported item IDs")
        compare(imported.allSatisfy { $0.revision == .initial && !$0.isArchived }, "imports untouched by the reset")

        let seedBytes = try Data(contentsOf: try #require(Bundle.main.url(forResource: "seed", withExtension: "json")))
        let record = try EvidenceRecord(
            subject: "LAB-007",
            check: Self.check,
            date: started,
            provenance: .current,
            execution: .fixture,
            inputs: [
                "seed:app-bundle@sha256:\(ContentDigest.sha256(seedBytes).hex)",
                "script:share-ingress@sha256:\(ContentDigest.sha256(script.bytes).hex)",
            ] + (try HostShareIngress.intakeFiles.map { "intake:\($0)@sha256:\(ContentDigest.sha256(try ShareIngressFixtures.intake($0)).hex)" })
              + ["link:\(HostShareIngress.link.absoluteString)",
                 "hostile:malformed-utf8.txt@sha256:\(ContentDigest.sha256(try ShareIngressFixtures.hostile("malformed-utf8.txt")).hex)"],
            steps: [
                "xcodebuild -scheme LabMac-Core -only-testing:LabMacTests/ShareIngressHostEvidenceTests test",
                "Each run on a fresh SQLite store in the app container, seeded by the host's first run (Reset Demo), with fresh inbox folders",
                "Refusal: ill-formed UTF-8 text and a link with a password, in one paste (fallback run) or one share (extension run)",
                "Fallback run: ShareInboxModel.paste of intake/harbor-walk.txt, then of the link, then importFiles of intake/gull-count.txt, each a second apart",
                "Extension run: IngressStation on the share extension's folder receives one extension item holding the link, the note, intake/harbor-sketch.png, and intake/tide-clip.mov; the inbox reads that folder",
                "create-collection: Field notes, with the showcase's collection ID, through LabLibrary.submit as New Collection… does",
                "add-note, add-link: ShareInboxModel.add into Field notes, which issues the one-item grant and commits through LabLibrary.adoptImport",
                "The same note again, then Add: expected to return the first receipt",
                "Archive one demo sample, then Reset Demo from the app",
                "Read both SQLite stores and compare",
            ],
            outcome: differences.isEmpty
                ? .passed(observed: "All \(comparisons) comparisons matched. Both hostile items were refused by position and kept nothing. The fallback staged the note and the link as Paste and the text file as File picker; the share staged the link, the note, the image, and the movie as Share sheet, positions 1 to 4 of 4. In both runs the two Adds committed exactly the showcase's createItem operations under its request IDs, the receipts naming App UI for the fallback and Share extension for the extension's folder. Adding the same note again returned the first receipt, listed once. Reset Demo restored only the archived sample. Both stores hold the same 4 collections and 14 items, field for field; the two imports are at revision 1. Only the files still wait.")
                : .failed(observed: "\(differences.count) of \(comparisons) comparisons differed: " + differences.joined(separator: "; ") + "."),
            limitations: [
                "Fixture path: hosted tests in the sandboxed Mac app on the development Mac, on fresh stores seeded from the bundled demo seed. It supports implemented at most.",
                "No share sheet ran. The Mac build has no share extension; its side was played by IngressStation, the code the iOS extension runs, on a folder the host reads as it reads the App Group folder.",
                "The paste and the file picker were driven through ShareInboxModel, not the Paste button, the pasteboard, or the open panel. The open panel is covered by a separate manual run.",
                "Files, images, and movies stage and wait; this build cannot add them to a collection.",
                "No physical iPhone or iPad and no iOS simulator ran in this check.",
            ]
        )
        Attachment.record(try Self.json(record), named: "LAB-007-share-ingress-host-intake-to-receipt.json")
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

/// The showcase interaction in the host, through one intake.
@MainActor
enum HostShareIngress {
    enum Intake {
        case paste
        case shareSheet
    }

    static let link = URL(string: "https://example.org/tide-tables")!
    static let intakeFiles = ["harbor-walk.txt", "gull-count.txt", "harbor-sketch.png", "tide-clip.mov"]
    /// The demo sample each run archives before Reset Demo: the seed's first item.
    static let archivedSample = ItemID(rawValue: UUID(uuidString: "DB666EF1-F642-43F1-B415-895B6ECFF693")!)

    /// The parts of `script.json` the host run needs: the collection and the two additions.
    struct Script {
        struct Addition {
            let step: String
            let request: RequestID
            let draft: ItemDraft
        }

        let bytes: Data
        let collectionRequest: RequestID
        let collection: CollectionDraft
        let additions: [Addition]

        static func load() throws -> Script {
            let bytes = try Data(contentsOf: ShareIngressFixtures.showcase.appending(path: "script.json"))
            let object = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            let steps = try #require(object["steps"] as? [[String: Any]])
            func uuid(_ value: Any?) throws -> UUID { try #require((value as? String).flatMap(UUID.init(uuidString:))) }
            var collection: (RequestID, CollectionDraft)?
            var additions: [Addition] = []
            for step in steps {
                if let body = step["createCollection"] as? [String: Any] {
                    collection = (RequestID(rawValue: try uuid(step["request"])), CollectionDraft(
                        id: CollectionID(rawValue: try uuid(body["id"])), title: try EntityTitle(try #require(body["title"] as? String))
                    ))
                }
                if let body = step["createItem"] as? [String: Any] {
                    additions.append(Addition(
                        step: try #require(step["id"] as? String),
                        request: RequestID(rawValue: try uuid(step["request"])),
                        draft: ItemDraft(
                            id: ItemID(rawValue: try uuid(body["id"])), in: CollectionID(rawValue: try uuid(body["collection"])),
                            title: try EntityTitle(try #require(body["title"] as? String)), note: try ItemNote(try #require(body["note"] as? String))
                        )
                    ))
                }
            }
            let (request, draft) = try #require(collection)
            return Script(bytes: bytes, collectionRequest: request, collection: draft, additions: additions)
        }
    }

    struct Arrival: Equatable {
        let surface: IngressSurface
        let position: Int
        let count: Int
        let kind: String
    }

    struct Outcome {
        var shareSheetStatus: ShareInboxModel.ShareSheetStatus = .notInThisBuild
        var refusedPositions: [Int] = []
        var leftAfterRefusal = -1
        var arrivals: [Arrival] = []
        var additions: [String: ReceiptRecord] = [:]
        var duplicateWasRecognized = false
        var resetChanges: [EntityReference] = []
        var stillWaiting: [String] = []
        var collections: [LabCollection] = []
        var items: [LabItem] = []
    }

    static func run(_ intake: Intake, script: Script, in folder: URL) async throws -> Outcome {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let hostRoot = folder.appending(path: "Share Inbox")
        let groupRoot = folder.appending(path: "group")
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let inbox = ShareInboxModel(locateHost: { hostRoot }, sharedRoot: intake == .shareSheet ? groupRoot : nil)
        await inbox.start()
        try #require(inbox.phase == .ready)
        let extensionSide = try IngressStation(area: IngressArea(source: .shareExtension, root: groupRoot))
        var outcome = Outcome(shareSheetStatus: inbox.shareSheet)

        let note = String(decoding: try ShareIngressFixtures.intake("harbor-walk.txt"), as: UTF8.self)
        let malformed = try ShareIngressFixtures.hostile("malformed-utf8.txt")
        func hostile() -> [NSItemProvider] {
            let bytes = NSItemProvider()
            bytes.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                completion(malformed, nil)
                return nil
            }
            return [bytes, NSItemProvider(object: URL(string: "https://user:secret@example.org/")! as NSURL)]
        }

        // Refusal first: nothing it held is kept, and nothing about it blocks what follows.
        let refusal: IntakeReport
        switch intake {
        case .paste:
            inbox.paste(hostile())
            await inbox.waitForIntake()
            refusal = try #require(inbox.lastReport)
        case .shareSheet:
            refusal = await extensionSide.receive(ItemProviderAttachment.attachments(from: hostile()), via: .shareExtension)
            await inbox.refresh()
        }
        outcome.refusedPositions = refusal.outcomes.filter(\.isRefused).map(\.position)
        outcome.leftAfterRefusal = inbox.snapshot.entries.count + inbox.snapshot.quarantined.count

        // The intake.
        switch intake {
        case .paste:
            inbox.paste([NSItemProvider(object: note as NSString)])
            await inbox.waitForIntake()
            try await Task.sleep(for: .milliseconds(1_100))
            inbox.paste([NSItemProvider(object: link as NSURL)])
            await inbox.waitForIntake()
            try await Task.sleep(for: .milliseconds(1_100))
            let chosen = folder.appending(path: "gull-count.txt")
            try ShareIngressFixtures.intake("gull-count.txt").write(to: chosen)
            inbox.importFiles([chosen])
            await inbox.waitForIntake()
        case .shareSheet:
            let item = NSExtensionItem()
            item.attachments = [
                NSItemProvider(object: link as NSURL),
                NSItemProvider(object: note as NSString),
                try fileProvider("harbor-sketch.png", type: .png, suggestedName: "Harbor sketch", in: folder),
                try fileProvider("tide-clip.mov", type: .quickTimeMovie, suggestedName: "Tide clip", in: folder),
            ]
            #expect(await extensionSide.receive(ItemProviderAttachment.attachments(from: [item]), via: .shareExtension).stagedCount == 4)
            await inbox.refresh()
        }
        outcome.arrivals = inbox.snapshot.entries.map {
            Arrival(surface: $0.origin?.surface ?? .drop, position: $0.origin?.position ?? 0, count: $0.origin?.count ?? 0, kind: $0.content.kindName)
        }

        // The review: New Collection…, then Add for each addition the script lists.
        _ = try await library.submit(
            .createCollection(draft: script.collection), requestID: script.collectionRequest, authority: .userAction,
            names: [.collection(script.collection.id): script.collection.title.value]
        )
        await inbox.loadCollections(from: library)
        #expect(inbox.destinationID == script.collection.id)
        for addition in script.additions {
            let expected = addition.draft.note.value
            let entry = try #require(inbox.snapshot.entries.first { entry in
                switch entry.content {
                case .text(let text): text == expected
                case .link(let url, _): url.absoluteString == expected
                case .files: false
                }
            })
            let added = try #require(await inbox.add(entry, to: script.collection.id, in: library), "\(addition.step)")
            #expect(!added.isDuplicate)
            outcome.additions[addition.step] = added.record
        }

        // The same note again, through the same intake: the Add returns its first receipt.
        let listed = library.receipts.count
        switch intake {
        case .paste:
            inbox.paste([NSItemProvider(object: note as NSString)])
            await inbox.waitForIntake()
        case .shareSheet:
            _ = await extensionSide.receive(ItemProviderAttachment.attachments(from: [NSItemProvider(object: note as NSString)]), via: .shareExtension)
            await inbox.refresh()
        }
        if let again = inbox.snapshot.entries.first(where: { $0.content == .text(note) }),
           let duplicate = await inbox.add(again, to: script.collection.id, in: library) {
            outcome.duplicateWasRecognized = duplicate.isDuplicate
                && duplicate.record == outcome.additions["add-note"]
                && library.receipts.count == listed
        }

        // Reset Demo after changing one sample.
        let sample = try #require(library.collections.flatMap(\.items).first { $0.id == archivedSample })
        #expect(await library.setArchived(sample, true) != nil)
        outcome.resetChanges = try #require(await library.resetDemo()).receipt.changes.map(\.entity)

        await inbox.refresh()
        outcome.stillWaiting = inbox.snapshot.entries.map(\.content.kindName)
        let store = try await SQLiteOperationStore(url: storeURL)
        outcome.collections = try await store.collections().sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        outcome.items = try await store.items(in: nil).sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        return outcome
    }

    /// A file-backed item as Photos provides it: the file exists only while the handler runs.
    private static func fileProvider(_ name: String, type: UTType, suggestedName: String, in folder: URL) throws -> NSItemProvider {
        let source = folder.appending(path: "source-\(UUID().uuidString)")
        try ShareIngressFixtures.intake(name).write(to: source)
        let provider = NSItemProvider()
        provider.suggestedName = suggestedName
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            completion(source, false, nil)
            return nil
        }
        return provider
    }
}
