import Foundation
import LabDomain
import LabStaging
import Testing
import UniformTypeIdentifiers
@testable import ShareIngress

/// LAB-007-B step 1: the showcase interaction (`Fixtures/showcase/share-ingress/`) from a clean
/// state, through the real intake, the inbox, and `ImportAdopter`, the path the host's Add takes.
///
/// `Packages/LabDemo` replays the script's changes as evidence, starting where the review ends.
/// Here the same script is run from the intake: the note and the link are pasted, a text file is
/// chosen in the file picker, and in a second clean lab the same content arrives in one share
/// through the share extension's folder. Each Add must commit exactly the script's `createItem`
/// step, with its item ID and request ID, and both labs must end in the same state.
///
/// LabFeatures does not depend on LabDemo, so the script is read as plain JSON. A step kind this
/// file does not map fails the test rather than being skipped.
@Suite struct ShareIngressShowcaseReplayTests {
    @Test func thePasteFallbackCommitsExactlyTheScriptsAdditions() async throws {
        let showcase = try ShareIngressShowcaseFile.load()
        let replay = try await ShareIngressShowcaseReplay.run(showcase, through: .paste)

        // The intake: two pastes and one chosen file, in arrival order, with their origins.
        #expect(replay.arrived.map(\.surface) == [.paste, .paste, .filePicker])
        #expect(replay.arrived.map(\.kind) == ["text", "link", "files"])
        #expect(replay.arrived.allSatisfy { $0.position == 1 && $0.count == 1 })

        // Every Add committed the script's operation under the script's request ID, as the app UI.
        #expect(replay.additions.count == 2)
        for addition in replay.additions {
            #expect(addition.receipt.admitted.adapter == .appUI, "\(addition.step)")
            #expect(addition.receipt.status == .committed)
        }
        #expect(replay.reads.map(\.0) == showcase.expectedReads.map(\.0))
        for ((step, found), (_, expected)) in zip(replay.reads, showcase.expectedReads) {
            #expect(found == expected, "\(step)")
        }

        // The chosen file is still waiting: a file cannot be added in this build.
        #expect(replay.stillWaiting.map(\.content.kindName) == ["files"])
        #expect(replay.stillWaiting.allSatisfy { $0.adoptability == .unavailable(.attachmentsNotAdoptable) })
        #expect(replay.collections.count == 4 && replay.items.count == 14)
    }

    @Test func oneShareOfTheSameContentCommitsTheSameAdditionsAsTheShareExtension() async throws {
        let showcase = try ShareIngressShowcaseFile.load()
        let pasted = try await ShareIngressShowcaseReplay.run(showcase, through: .paste)
        let shared = try await ShareIngressShowcaseReplay.run(showcase, through: .shareSheet)

        // One share of a link, the note, an image, and a movie: four imports in the share's order.
        #expect(shared.arrived.map(\.surface) == Array(repeating: .shareExtension, count: 4))
        #expect(shared.arrived.map(\.position) == [1, 2, 3, 4])
        #expect(shared.arrived.allSatisfy { $0.count == 4 })
        #expect(shared.arrived.map(\.contentType) == [
            UTType.url.identifier, UTType.utf8PlainText.identifier, UTType.png.identifier, UTType.quickTimeMovie.identifier,
        ])

        // The same additions, committed as the share extension this time.
        #expect(shared.additions.count == 2)
        for (fromPaste, fromShare) in zip(pasted.additions, shared.additions) {
            #expect(fromPaste.step == fromShare.step)
            #expect(fromShare.receipt.admitted.adapter == .shareExtension)
            #expect(fromShare.receipt.requestID == fromPaste.receipt.requestID)
            #expect(fromShare.receipt.admitted.operation == fromPaste.receipt.admitted.operation)
            #expect(fromShare.receipt.changes == fromPaste.receipt.changes)
            #expect(fromShare.receipt.summary == fromPaste.receipt.summary)
            #expect(fromShare.receipt.undo == fromPaste.receipt.undo)
        }
        for ((step, found), (_, expected)) in zip(shared.reads, showcase.expectedReads) {
            #expect(found == expected, "\(step)")
        }

        // The same persisted state, whichever way the content came in.
        #expect(shared.collections == pasted.collections)
        #expect(shared.items == pasted.items)

        // The image and the movie wait; they cannot be added in this build.
        #expect(shared.stillWaiting.map(\.content.kindName) == ["files", "files"])
        #expect(shared.stillWaiting.map(\.headline) == ["Harbor sketch.png", "Tide clip.mov"])
    }
}

// MARK: - The showcase file

/// `Fixtures/showcase/share-ingress/`, decoded into the steps this file replays.
struct ShareIngressShowcaseFile {
    static let folder = HostileFixtures.folder.deletingLastPathComponent().appending(path: "showcase/share-ingress", directoryHint: .isDirectory)
    static let link = URL(string: "https://example.org/tide-tables")!

    static func intake(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: "intake/\(name)"))
    }

    enum Action {
        case approve(target: String)
        case resetDemo(request: RequestID)
        case createCollection(request: RequestID, draft: CollectionDraft)
        case createItem(request: RequestID, draft: ItemDraft)
        case find(filter: ItemFilter, expect: [ItemID])
    }

    struct Step {
        let id: String
        let action: Action
    }

    let seed: DemoSeed
    let steps: [Step]

    var expectedReads: [(String, [ItemID])] {
        steps.compactMap { step in
            if case .find(_, let expect) = step.action { (step.id, expect) } else { nil }
        }
    }

    static func load() throws -> ShareIngressShowcaseFile {
        let seed = try JSONDecoder().decode(ShowcaseSeedFile.self, from: Data(contentsOf: folder.appending(path: "seed.json")))
        let script = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "script.json"))) as? [String: Any]
        )
        #expect(script["subject"] as? String == "LAB-007")
        let steps = try #require(script["steps"] as? [[String: Any]])
        return ShareIngressShowcaseFile(seed: try seed.demoSeed(), steps: try steps.map(Self.step))
    }

    private static func step(_ object: [String: Any]) throws -> Step {
        let id = try #require(object["id"] as? String)
        let request = (object["request"] as? String).flatMap(UUID.init(uuidString:)).map(RequestID.init(rawValue:))
        func uuid(_ value: Any?) throws -> UUID { try #require((value as? String).flatMap(UUID.init(uuidString:))) }
        func payload(_ key: String) throws -> [String: Any] { try #require(object[key] as? [String: Any]) }
        let known = Set(object.keys).subtracting(["id", "description", "request"])
        try #require(known.count == 1, "one action in \(id)")
        switch known.first {
        case "approve":
            return Step(id: id, action: .approve(target: try #require(object["approve"] as? String)))
        case "resetDemo":
            return Step(id: id, action: .resetDemo(request: try #require(request)))
        case "createCollection":
            let body = try payload("createCollection")
            return Step(id: id, action: .createCollection(request: try #require(request), draft: CollectionDraft(
                id: CollectionID(rawValue: try uuid(body["id"])), title: try EntityTitle(try #require(body["title"] as? String))
            )))
        case "createItem":
            let body = try payload("createItem")
            return Step(id: id, action: .createItem(request: try #require(request), draft: ItemDraft(
                id: ItemID(rawValue: try uuid(body["id"])), in: CollectionID(rawValue: try uuid(body["collection"])),
                title: try EntityTitle(try #require(body["title"] as? String)), note: try ItemNote(body["note"] as? String ?? "")
            )))
        case "find":
            let body = try payload("find")
            return Step(id: id, action: .find(
                filter: try ItemFilter(
                    collectionID: try body["collection"].map { CollectionID(rawValue: try uuid($0)) },
                    text: body["text"] as? String,
                    includeArchived: body["includeArchived"] as? Bool ?? false
                ),
                expect: try #require(body["expect"] as? [String]).map { ItemID(rawValue: try #require(UUID(uuidString: $0))) }
            ))
        default:
            Issue.record("Step \(id) has an action this replay does not map: \(known.sorted())")
            throw ShareIngressShowcaseError.unmappedStep(id)
        }
    }
}

enum ShareIngressShowcaseError: Error {
    case unmappedStep(String)
    case noImportMatches(String)
}

/// The demo seed format, read without LabStore.
struct ShowcaseSeedFile: Decodable {
    struct Collection: Decodable {
        let id: UUID
        let title: String
    }

    struct Item: Decodable {
        let id: UUID
        let collection: UUID
        let title: String
        let note: String?
    }

    let seedVersion: Int
    let collections: [Collection]
    let items: [Item]

    func demoSeed() throws -> DemoSeed {
        try DemoSeed(
            version: seedVersion,
            collections: try collections.map { CollectionDraft(id: CollectionID(rawValue: $0.id), title: try EntityTitle($0.title)) },
            items: try items.map {
                ItemDraft(
                    id: ItemID(rawValue: $0.id), in: CollectionID(rawValue: $0.collection),
                    title: try EntityTitle($0.title), note: try ItemNote($0.note ?? "")
                )
            }
        )
    }
}

// MARK: - Replay from the intake

/// The host's composition in a clean lab: one ledger, one in-memory store, one service, and the
/// staging folders, as `LabDataService` and `ShareInboxModel` build them.
struct ShowcaseLab {
    let folders: Station
    let ledger: GrantLedger
    let store = InMemoryOperationStore()
    let service: OperationService

    init(ledger: GrantLedger = GrantLedger()) throws {
        folders = try Station()
        self.ledger = ledger
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
    }

    /// What the host's Add does: a grant for exactly this import's operation, for the adapter its
    /// folder names, revoked when the commit returns.
    func add(_ entry: InboxEntry, into collection: CollectionID) async throws(ImportRejection) -> ImportAdoption {
        let inbox = folders.inbox
        guard let area = await inbox.area(for: entry.source) else { throw .notFound }
        let record = try await area.staging.validatedRecord(entry.id.staging)
        let operation = try ImportAdopter.operation(for: record, into: collection)
        let grant = try? ledger.issue(for: operation, to: entry.source.adapter, lifetime: .seconds(30))
        defer { if let grant { ledger.revoke(grant.id) } }
        let adoption = try await ImportAdopter(service: service, inbox: area.staging, ledger: ledger, adapter: entry.source.adapter)
            .adopt(entry.id.staging, into: collection)
        await inbox.didAdopt(entry.id)
        return adoption
    }

    /// A change the person confirmed, such as Reset Demo, committed as the app UI.
    func confirm(_ operation: DomainOperation, request: RequestID) async throws -> ActionReceipt {
        let grant = try ledger.issue(for: operation, to: .appUI)
        defer { ledger.revoke(grant.id) }
        return try await service.perform(OperationRequest(id: request, operation: operation, actor: .testAppUI))
    }
}

struct ShareIngressShowcaseReplay {
    enum Intake {
        /// Paste the note, then the link, then choose the text file, into the host's folder.
        case paste
        /// One share of the link, the note, the image, and the movie, into the share extension's folder.
        case shareSheet
    }

    struct Arrival {
        let surface: IngressSurface
        let position: Int
        let count: Int
        let contentType: String?
        let kind: String
    }

    struct Addition {
        let step: String
        let receipt: ActionReceipt
    }

    var arrived: [Arrival] = []
    var additions: [Addition] = []
    var reads: [(String, [ItemID])] = []
    var stillWaiting: [InboxEntry] = []
    var collections: [LabCollection] = []
    var items: [LabItem] = []

    static func run(_ showcase: ShareIngressShowcaseFile, through intake: Intake) async throws -> ShareIngressShowcaseReplay {
        let lab = try ShowcaseLab()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let note = String(decoding: try ShareIngressShowcaseFile.intake("harbor-walk.txt"), as: UTF8.self)

        switch intake {
        case .paste:
            // Seconds apart, as a person pastes: the inbox lists intakes by the second they began.
            let first = IngressStation(area: lab.folders.host, now: { start })
            let second = IngressStation(area: lab.folders.host, now: { start + 5 })
            let third = IngressStation(area: lab.folders.host, now: { start + 10 })
            #expect(await first.receive(ItemProviderAttachment.attachments(from: [Providers.text(note)], acceptsFileReferences: true), via: .paste).stagedCount == 1)
            #expect(await second.receive(ItemProviderAttachment.attachments(from: [Providers.link(ShareIngressShowcaseFile.link.absoluteString)], acceptsFileReferences: true), via: .paste).stagedCount == 1)
            let chosen = lab.folders.folder.appending(path: "gull-count.txt")
            try ShareIngressShowcaseFile.intake("gull-count.txt").write(to: chosen)
            #expect(await third.receive(ChosenFile.attachments(from: [chosen]), via: .filePicker).stagedCount == 1)
        case .shareSheet:
            let item = NSExtensionItem()
            item.attachments = [
                Providers.link(ShareIngressShowcaseFile.link.absoluteString),
                Providers.text(note),
                try Providers.file(try ShareIngressShowcaseFile.intake("harbor-sketch.png"), type: .png, suggestedName: "Harbor sketch", folder: lab.folders.folder),
                try Providers.file(try ShareIngressShowcaseFile.intake("tide-clip.mov"), type: .quickTimeMovie, suggestedName: "Tide clip", folder: lab.folders.folder),
            ]
            let station = IngressStation(area: lab.folders.shared, now: { start })
            #expect(await station.receive(ItemProviderAttachment.attachments(from: [item]), via: .shareExtension).stagedCount == 4)
        }

        var replay = ShareIngressShowcaseReplay()
        let snapshot = await lab.folders.inbox.snapshot()
        replay.arrived = snapshot.entries.map { entry in
            Arrival(
                surface: entry.origin?.surface ?? .drop, position: entry.origin?.position ?? 0, count: entry.origin?.count ?? 0,
                contentType: entry.origin?.contentType, kind: entry.content.kindName
            )
        }

        var approved = Set<String>()
        for step in showcase.steps {
            switch step.action {
            case .approve(let target):
                approved.insert(target)
            case .resetDemo(let request):
                try #require(approved.contains(step.id), "Reset Demo runs only after its confirmation")
                let receipt = try await lab.confirm(.resetDemo(seed: showcase.seed), request: request)
                #expect(receipt.status == .committed)
            case .createCollection(let request, let draft):
                let receipt = try await lab.service.perform(OperationRequest(id: request, operation: .createCollection(draft: draft), actor: .testAppUI))
                #expect(receipt.status == .committed)
            case .createItem(let request, let draft):
                try #require(approved.contains(step.id), "an Add runs only after the person chooses it")
                // The review: find the waiting import whose Add is exactly this step's change.
                var match: InboxEntry?
                for entry in await lab.folders.inbox.snapshot().entries where entry.adoptability == .ready {
                    guard let area = await lab.folders.inbox.area(for: entry.source) else { continue }
                    let record = try await area.staging.validatedRecord(entry.id.staging)
                    if try ImportAdopter.operation(for: record, into: draft.collectionID) == .createItem(draft: draft),
                       ImportAdopter.requestID(for: record, into: draft.collectionID) == request {
                        match = entry
                    }
                }
                guard let entry = match else { throw ShareIngressShowcaseError.noImportMatches(step.id) }
                let adoption = try await lab.add(entry, into: draft.collectionID)
                #expect(!adoption.isDuplicate)
                #expect(adoption.receipt.requestID == request, "\(step.id)")
                #expect(adoption.receipt.admitted.operation == .createItem(draft: draft), "\(step.id)")
                replay.additions.append(Addition(step: step.id, receipt: adoption.receipt))
            case .find(let filter, _):
                replay.reads.append((step.id, try await lab.service.findItems(filter, as: .testAppUI).map(\.id)))
            }
        }

        let after = await lab.folders.inbox.snapshot()
        #expect(after.quarantined.isEmpty)
        replay.stillWaiting = after.entries
        replay.collections = await lab.store.collections().sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        replay.items = await lab.store.items(in: nil).sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        return replay
    }
}
