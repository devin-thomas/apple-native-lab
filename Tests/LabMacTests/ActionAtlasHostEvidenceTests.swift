import ActionAtlas
import Foundation
import LabDomain
import LabStore
import LabSupport
import Testing
@testable import NativeLab

/// LAB-001-B criterion 3 with its evidence: the showcase interaction (`Fixtures/showcase/
/// action-atlas/`, the same request IDs) run in the sandboxed Mac app through the in-app action
/// browser's path and through the App Intent types, each on a fresh SQLite store that the host's
/// first run seeds. The persisted states must be identical.
///
/// The test attaches an `EvidenceRecord` of what it observed, with the toolchain read from this
/// app bundle. To keep it, run the test with a result bundle and export the attachment:
///
///     xcodebuild … -scheme LabMac-Core -only-testing:LabMacTests/ActionAtlasHostEvidenceTests \
///       -resultBundlePath <bundle> LAB_SOURCE_REVISION=<sha> test
///     xcrun xcresulttool export attachments --path <bundle> --output-path <folder>
@MainActor
@Suite struct ActionAtlasHostEvidenceTests {
    static let check = "Action Atlas showcase interaction in the Mac host: the action browser's path and the App Intent types leave identical persisted state"

    @Test func theShowcaseInteractionLeavesIdenticalStateFromBothEntryPoints() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ActionAtlasHostEvidenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let started = Date()

        let ui = try await HostShowcase.run(through: .appUI, in: folder.appending(path: "ui"))
        let intent = try await HostShowcase.run(through: .appIntent, in: folder.appending(path: "intent"))

        // Every comparison is counted, and any difference is named in the record.
        var differences: [String] = []
        func compare(_ same: Bool, _ what: String) {
            #expect(same, "\(what)")
            if !same { differences.append(what) }
        }
        for (step, expected) in HostShowcase.expectedReads {
            compare(ui.reads[step] == expected, "app-UI read \(step)")
            compare(intent.reads[step] == expected, "App Intent read \(step)")
        }
        compare(ui.collections == intent.collections, "collections")
        compare(ui.items == intent.items, "items")
        compare(ui.collections.count == 4 && ui.items.count == 13, "4 collections and 13 items")
        for request in HostShowcase.requests {
            let fromUI = ui.receipts[request.id]
            let fromIntent = intent.receipts[request.id]
            compare(fromUI?.admitted.adapter == .appUI, "\(request.step) receipt names App UI")
            compare(fromIntent?.admitted.adapter == .appIntent, "\(request.step) receipt names App Intent")
            compare(fromUI?.admitted.operation == fromIntent?.admitted.operation, "\(request.step) operation")
            compare(fromUI?.status == fromIntent?.status, "\(request.step) status")
            compare(fromUI?.changes == fromIntent?.changes, "\(request.step) changes")
            compare(fromUI?.removed == fromIntent?.removed, "\(request.step) removals")
            compare(fromUI?.summary == fromIntent?.summary, "\(request.step) summary")
            compare(fromUI?.undo == fromIntent?.undo, "\(request.step) undo")
        }
        compare(ui.reset?.changes == intent.reset?.changes && ui.reset?.summary == intent.reset?.summary, "second Reset Demo")
        compare(ui.reset?.changes.map(\.entity) == [.item(HostShowcase.amber)], "second Reset Demo touched only the renamed sample")

        let seedBytes = try Data(contentsOf: try #require(Bundle.main.url(forResource: "seed", withExtension: "json")))
        let comparisons = HostShowcase.expectedReads.count * 2 + 3 + HostShowcase.requests.count * 8 + 2
        let record = try EvidenceRecord(
            subject: "LAB-001",
            check: Self.check,
            date: started,
            provenance: .current,
            execution: .fixture,
            inputs: [
                "seed:app-bundle@sha256:\(ContentDigest.sha256(seedBytes).hex)",
                "requests:" + HostShowcase.requests.map { "\($0.step)=\($0.id)" }.joined(separator: ","),
            ],
            steps: [
                "xcodebuild -scheme LabMac-Core -only-testing:LabMacTests/ActionAtlasHostEvidenceTests test",
                "Each entry point on a fresh SQLite store in the app container, seeded by the host's first run (Reset Demo)",
            ] + HostShowcase.stepDescriptions,
            outcome: differences.isEmpty
                ? .passed(observed: "All \(comparisons) comparisons matched. Both stores hold the same 4 collections and 13 items, field for field. The 6 Action Atlas receipts match in operation, status, changes, removals, summary, and undo, and each names its entry point: app-ui for the action browser's path, app-intent for the intent types. Every one of the 8 reads returned the expected items from both entry points. The second Reset Demo restored only the renamed sample and left the person's collection and item alone.")
                : .failed(observed: "\(differences.count) of \(comparisons) comparisons differed: " + differences.joined(separator: "; ") + "."),
            limitations: [
                "Fixture path: hosted tests in the sandboxed Mac app on the development Mac, on fresh stores seeded from the bundled demo seed. It supports implemented at most.",
                "The intents ran through run(with:), the call their perform() makes after the system's dialogs. Shortcuts, Siri, Spotlight, and the system's confirmation and disambiguation dialogs did not run; a stand-in approved the one confirmation.",
                "Operation IDs, and the receipts of the Reset Demos, whose request IDs the host makes at random, are left out of the receipt comparison by design; the second Reset Demo is compared by its changes and summary.",
                "No physical iPhone or iPad and no iOS simulator ran in this check.",
            ]
        )
        Attachment.record(try Self.json(record), named: "LAB-001-action-atlas-host-ui-and-intent.json")
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

/// The showcase interaction after its first Reset Demo, which the host's first run performs.
@MainActor
enum HostShowcase {
    struct Request {
        let step: String
        let id: RequestID

        init(_ step: String, _ uuid: String) {
            self.step = step
            id = RequestID(rawValue: UUID(uuidString: uuid)!)
        }

        var atlas: AtlasRequest { AtlasRequest(id) }
    }

    static let requests = [
        Request("create-collection", "BD1CF7CD-9082-4135-BDE0-48953A92C51B"),
        Request("create-item", "1F8B4B32-F4DB-4B83-B38B-E71A907BF8B8"),
        Request("update-item", "ECA3A07F-3857-4B7A-B775-B2735070424F"),
        Request("update-sample", "C41C9EC0-EC7E-4E21-A794-CF0A0D718C9E"),
        Request("archive-item", "034ACB7C-C530-4EE1-9648-32B2B29392D7"),
        Request("undo-archive", "112ECEA7-CE96-4666-A8B2-598D2181C139"),
    ]

    static let fieldNotes = CollectionID(rawValue: UUID(uuidString: "7EDF340E-5341-42F6-BE23-8B56F95106D8")!)
    static let graphite = ItemID(rawValue: UUID(uuidString: "45D11168-AE81-41D9-A9D1-BD40CA21A2E2")!)
    static let amber = ItemID(rawValue: UUID(uuidString: "DB666EF1-F642-43F1-B415-895B6ECFF693")!)
    static let pigments = CollectionID(rawValue: UUID(uuidString: "A40194B3-5E91-4C5C-AE02-CF703BE23224")!)
    static let swatches = ["DB666EF1-F642-43F1-B415-895B6ECFF693", "9B97BF2F-4D0B-4197-9CA8-36489DF40455",
                           "C8E1904C-E8DC-40A0-93D3-53F6C0FFF95D", "3A1711A8-E1DB-489E-8321-414266A8DF49"]
        .map { ItemID(rawValue: UUID(uuidString: $0)!) }

    static let expectedReads: [(String, [ItemID])] = [
        ("find-graphite", [graphite]),
        ("find-swatches", swatches),
        ("find-renamed", [amber]),
        ("find-after-archive", []),
        ("find-archived", [graphite]),
        ("find-after-undo", [graphite]),
        ("find-after-reset", []),
        ("find-yours-after-reset", [graphite]),
    ]

    static let stepDescriptions = [
        "create-collection: Create Lab Collection “Field notes”",
        "create-item: Create Lab Item “Graphite stick” (note “Soft, 6B.”) in it",
        "find-graphite: Find Lab Items “graphite”",
        "find-swatches: Find Lab Items in Pigment swatches",
        "update-item: Update Lab Item note to “Soft, 6B. Smudges easily.”",
        "update-sample: Update Lab Item “Amber swatch” title to “Amber swatch, matte”",
        "find-renamed: Find Lab Items “SWATCH, MATTE”",
        "archive-item: Archive Lab Item “Graphite stick”, confirmed",
        "find-after-archive, find-archived: Find Lab Items “graphite” without and with archived items",
        "undo-archive: the archive receipt's undo, run as Restore Lab Item",
        "find-after-undo: Find Lab Items “graphite”",
        "reset-again: Reset Demo from the app",
        "find-after-reset: Find Lab Items “swatch, matte”; find-yours-after-reset: Find Lab Items “smudges” in Field notes",
    ]

    struct Outcome {
        var reads: [String: [ItemID]] = [:]
        var receipts: [RequestID: ActionReceipt] = [:]
        var reset: ActionReceipt?
        var collections: [LabCollection] = []
        var items: [LabItem] = []
    }

    /// Runs the interaction through one entry point on a new store in `folder`.
    static func run(through entryPoint: AtlasEntryPoint, in folder: URL) async throws -> Outcome {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        let link = ActionAtlasLink(backend: LibraryAtlasBackend(library: library))
        let browser = library.atlasActions
        var outcome = Outcome()
        let request = Dictionary(uniqueKeysWithValues: requests.map { ($0.step, $0) })

        func find(_ step: String, text: String?, in collection: CollectionID? = nil, includeArchived: Bool = false) async throws {
            switch entryPoint {
            case .appUI:
                outcome.reads[step] = try await browser.findItems(text: text, in: collection, includeArchived: includeArchived).map(\.id)
            case .appIntent:
                let intent = FindItemsIntent()
                intent.text = text
                if let collection {
                    intent.collection = LabCollectionEntity(try await link.actions(.appIntent).collection(collection))
                }
                intent.includeArchived = includeArchived
                intent.limit = 50
                outcome.reads[step] = try await intent.run(with: link).value.map(\.itemID)
            }
        }

        func item(_ id: ItemID) async throws -> LabItemEntity {
            try #require(try await LabItemQuery.lookUp(id, link: link))
        }

        func keep(_ receipt: ActionReceipt?) {
            if let receipt { outcome.receipts[receipt.requestID] = receipt }
        }

        switch entryPoint {
        case .appUI:
            keep(try await browser.createCollection(title: "Field notes", request: request["create-collection"]!.atlas).receipt)
            keep(try await browser.createItem(title: "Graphite stick", note: "Soft, 6B.", in: fieldNotes, request: request["create-item"]!.atlas).receipt)
        case .appIntent:
            let collection = CreateCollectionIntent()
            collection.title = "Field notes"
            collection.requestID = request["create-collection"]!.id.description
            let created = try await collection.run(with: link)
            keep(created.receipt)
            let newItem = CreateItemIntent()
            newItem.title = "Graphite stick"
            newItem.note = "Soft, 6B."
            newItem.collection = created.value
            newItem.requestID = request["create-item"]!.id.description
            keep(try await newItem.run(with: link).receipt)
        }
        try await find("find-graphite", text: "graphite")
        try await find("find-swatches", text: nil, in: pigments)

        switch entryPoint {
        case .appUI:
            keep(try await browser.updateItem(graphite, expected: .initial, title: nil, note: "Soft, 6B. Smudges easily.", request: request["update-item"]!.atlas).receipt)
            keep(try await browser.updateItem(amber, expected: .initial, title: "Amber swatch, matte", note: nil, request: request["update-sample"]!.atlas).receipt)
        case .appIntent:
            let note = UpdateItemIntent()
            note.item = try await item(graphite)
            note.newNote = "Soft, 6B. Smudges easily."
            note.requestID = request["update-item"]!.id.description
            keep(try await note.run(with: link).receipt)
            let rename = UpdateItemIntent()
            rename.item = try await item(amber)
            rename.newTitle = "Amber swatch, matte"
            rename.requestID = request["update-sample"]!.id.description
            keep(try await rename.run(with: link).receipt)
        }
        try await find("find-renamed", text: "SWATCH, MATTE")

        let archiveReceipt: ActionReceipt?
        switch entryPoint {
        case .appUI:
            archiveReceipt = try await browser.archiveItem(graphite, expected: Revision(rawValue: 2)!, request: request["archive-item"]!.atlas) { _ in }.receipt
        case .appIntent:
            let archive = ArchiveItemIntent()
            archive.item = try await item(graphite)
            archive.requestID = request["archive-item"]!.id.description
            archiveReceipt = try await archive.run(with: link) { _ in }.receipt
        }
        keep(archiveReceipt)
        try await find("find-after-archive", text: "graphite")
        try await find("find-archived", text: "graphite", includeArchived: true)

        guard case .restoreItem(let id, let expected)? = archiveReceipt?.undo else {
            Issue.record("the archive receipt offers a restore")
            return outcome
        }
        switch entryPoint {
        case .appUI:
            keep(try await browser.restoreItem(id, expected: expected, request: request["undo-archive"]!.atlas).receipt)
        case .appIntent:
            let restore = RestoreItemIntent()
            restore.item = try await item(id)
            restore.requestID = request["undo-archive"]!.id.description
            keep(try await restore.run(with: link).receipt)
        }
        try await find("find-after-undo", text: "graphite")

        // Reset Demo is the host's own action, whichever entry point ran the rest.
        outcome.reset = try #require(await library.resetDemo()).receipt
        try await find("find-after-reset", text: "swatch, matte")
        try await find("find-yours-after-reset", text: "smudges", in: fieldNotes)

        let store = try await SQLiteOperationStore(url: url)
        outcome.collections = try await store.collections().sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        outcome.items = try await store.items(in: nil).sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        return outcome
    }
}
