@testable import ActionAtlas
import Foundation
import LabDomain
import Testing

/// LAB-001-B step 1 and criterion 3: the showcase script that `Packages/LabDemo` replays as
/// evidence (`Fixtures/showcase/action-atlas/`), run here through Action Atlas itself, once from
/// the in-app action browser's entry point and once through the App Intent types, each from a
/// clean store. Both reach every read the script expects and the same persisted state.
///
/// LabFeatures does not depend on LabDemo, so the script is read as plain JSON. A step kind this
/// file does not map fails the test rather than being skipped.
@Suite struct ActionAtlasShowcaseReplayTests {
    @Test func theShowcaseCreatesWhatTheActionsWouldForTheSameRequestIDs() throws {
        let showcase = try ShowcaseFile.load()
        var created = 0
        for step in showcase.steps {
            switch step.action {
            case .createCollection(let request, let id, _):
                #expect(AtlasRequest(request).newCollectionID.rawValue == id, "\(step.id)")
                created += 1
            case .createItem(let request, let id, _, _, _):
                #expect(AtlasRequest(request).newItemID.rawValue == id, "\(step.id)")
                created += 1
            default:
                continue
            }
        }
        #expect(created == 2)
    }

    @Test func bothEntryPointsReplayTheShowcaseToIdenticalPersistedState() async throws {
        let showcase = try ShowcaseFile.load()
        let ui = try await ShowcaseReplay.run(showcase, through: .appUI)
        let intent = try await ShowcaseReplay.run(showcase, through: .appIntent)

        // Every read the script declares, from both entry points.
        for (step, expected) in showcase.expectedReads {
            #expect(ui.reads[step] == expected, "app UI, \(step)")
            #expect(intent.reads[step] == expected, "App Intent, \(step)")
        }
        #expect(ui.reads.count == 8 && intent.reads.count == 8)

        // The same persisted state.
        let uiState = await ui.backend.snapshot()
        let intentState = await intent.backend.snapshot()
        #expect(uiState.collections == intentState.collections)
        #expect(uiState.items == intentState.items)
        #expect(uiState.collections.count == 4 && uiState.items.count == 13)
        let graphite = try #require(uiState.items.first { $0.id == ShowcaseFile.graphite })
        #expect(graphite.namespace == .user && graphite.revision.rawValue == 4 && !graphite.isArchived)
        let amber = try #require(uiState.items.first { $0.id == ShowcaseFile.amber })
        #expect(amber.title.value == "Amber swatch" && amber.revision.rawValue == 3)

        // The same receipts, apart from the operation ID and the entry point each one names.
        #expect(ui.receipts.keys.sorted() == intent.receipts.keys.sorted())
        #expect(ui.receipts.count == 8)
        for (step, fromUI) in ui.receipts {
            let fromIntent = try #require(intent.receipts[step])
            let isHostReset = if case .resetDemo = fromUI.admitted.operation { true } else { false }
            #expect(fromUI.admitted.adapter == .appUI)
            #expect(fromIntent.admitted.adapter == (isHostReset ? .appUI : .appIntent), "\(step)")
            #expect(fromIntent.requestID == fromUI.requestID)
            #expect(fromIntent.admitted.operation == fromUI.admitted.operation, "\(step)")
            #expect(fromIntent.status == fromUI.status)
            #expect(fromIntent.changes == fromUI.changes, "\(step)")
            #expect(fromIntent.removed == fromUI.removed)
            #expect(fromIntent.summary == fromUI.summary)
            #expect(fromIntent.undo == fromUI.undo)
        }
        // The intent asked for the person's confirmation exactly once, for the archive.
        #expect(intent.confirmations == ["Archive “Graphite stick”? It leaves normal view without being deleted, and its receipt in Native Lab offers an undo."])
    }
}

// MARK: - The showcase file

/// `Fixtures/showcase/action-atlas/`, decoded into the steps this file can replay.
struct ShowcaseFile {
    static let folder = URL(filePath: #filePath)
        .deletingLastPathComponent() // ActionAtlasTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabFeatures
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository root
        .appending(path: "Fixtures/showcase/action-atlas", directoryHint: .isDirectory)

    static let graphite = ItemID(rawValue: UUID(uuidString: "45D11168-AE81-41D9-A9D1-BD40CA21A2E2")!)
    static let amber = ItemID(rawValue: UUID(uuidString: "DB666EF1-F642-43F1-B415-895B6ECFF693")!)

    enum Action {
        case approve(target: String)
        case resetDemo(request: RequestID)
        case createCollection(request: RequestID, id: UUID, title: String)
        case createItem(request: RequestID, id: UUID, collection: UUID, title: String, note: String?)
        case updateItem(request: RequestID, id: UUID, expected: Int, title: String?, note: String?)
        case archiveItem(request: RequestID, id: UUID, expected: Int)
        case undo(request: RequestID, of: String)
        case find(collection: UUID?, text: String?, includeArchived: Bool, limit: Int, expect: [UUID])
    }

    struct Step {
        let id: String
        let action: Action
    }

    let seed: DemoSeed
    let steps: [Step]

    /// Each find step and the item IDs it expects, in order.
    var expectedReads: [(String, [UUID])] {
        steps.compactMap { step in
            if case .find(_, _, _, _, let expect) = step.action { (step.id, expect) } else { nil }
        }
    }

    static func load() throws -> ShowcaseFile {
        let seed = try JSONDecoder().decode(SeedFile.self, from: Data(contentsOf: folder.appending(path: "seed.json")))
        let script = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "script.json"))) as? [String: Any]
        )
        #expect(script["seed"] as? String == "seed.json")
        let steps = try #require(script["steps"] as? [[String: Any]])
        return ShowcaseFile(seed: try seed.demoSeed(), steps: try steps.map(Self.step))
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
            return Step(id: id, action: .createCollection(
                request: try #require(request), id: try uuid(body["id"]), title: try #require(body["title"] as? String)
            ))
        case "createItem":
            let body = try payload("createItem")
            return Step(id: id, action: .createItem(
                request: try #require(request), id: try uuid(body["id"]), collection: try uuid(body["collection"]),
                title: try #require(body["title"] as? String), note: body["note"] as? String
            ))
        case "updateItem":
            let body = try payload("updateItem")
            return Step(id: id, action: .updateItem(
                request: try #require(request), id: try uuid(body["id"]), expected: try #require(body["expected"] as? Int),
                title: body["title"] as? String, note: body["note"] as? String
            ))
        case "archiveItem":
            let body = try payload("archiveItem")
            return Step(id: id, action: .archiveItem(
                request: try #require(request), id: try uuid(body["id"]), expected: try #require(body["expected"] as? Int)
            ))
        case "undo":
            return Step(id: id, action: .undo(request: try #require(request), of: try #require(object["undo"] as? String)))
        case "find":
            let body = try payload("find")
            return Step(id: id, action: .find(
                collection: try body["collection"].map { try uuid($0) },
                text: body["text"] as? String,
                includeArchived: body["includeArchived"] as? Bool ?? false,
                limit: body["limit"] as? Int ?? 50,
                expect: try #require(body["expect"] as? [String]).map { try #require(UUID(uuidString: $0)) }
            ))
        default:
            Issue.record("Step \(id) has an action this replay does not map: \(known.sorted())")
            throw ShowcaseFileError.unmappedStep(id)
        }
    }
}

enum ShowcaseFileError: Error {
    case unmappedStep(String)
    case unmappedUndo(String)
}

/// The demo seed format, read without LabStore.
private struct SeedFile: Decodable {
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

// MARK: - Replay through Action Atlas

/// What one entry point's replay left: its backend, each change's receipt, and each read.
struct ShowcaseReplay {
    let backend: TestBackend
    var receipts: [String: ActionReceipt] = [:]
    var reads: [String: [UUID]] = [:]
    var confirmations: [String] = []

    /// Replays every step from an empty store. Reset Demo is the host's own action, a control
    /// press in the app, whichever entry point runs the rest. An archive runs only after the
    /// script's approval step for it, which stands for the person's confirmation.
    static func run(_ showcase: ShowcaseFile, through entryPoint: AtlasEntryPoint) async throws -> ShowcaseReplay {
        var replay = ShowcaseReplay(backend: TestBackend())
        let spy = ConfirmationSpy()
        var approved = Set<String>()
        let actions = replay.backend.actions(entryPoint)
        let link = replay.backend.link
        let lookup = ItemLookup(actions: link.actions(.appIntent))

        func entity(_ id: UUID, at revision: Int) async throws -> LabItemEntity {
            let entity = try #require(try await lookup.entities(for: [ItemID(rawValue: id)]).first)
            #expect(entity.revision == revision, "the script's expected revision is the one the entity shows")
            return entity
        }

        for step in showcase.steps {
            let receipt: ActionReceipt?
            switch step.action {
            case .approve(let target):
                approved.insert(target)
                receipt = nil
            case .resetDemo(let request):
                receipt = try await replay.backend.commit(
                    .resetDemo(seed: showcase.seed), requestID: request, authority: .appControl, names: [:]
                )
            case .createCollection(let request, _, let title):
                switch entryPoint {
                case .appUI:
                    receipt = try await actions.createCollection(title: title, request: AtlasRequest(request)).receipt
                case .appIntent:
                    let intent = CreateCollectionIntent()
                    intent.title = title
                    intent.requestID = request.rawValue.uuidString
                    receipt = try await intent.run(with: link).receipt
                }
            case .createItem(let request, _, let collection, let title, let note):
                switch entryPoint {
                case .appUI:
                    receipt = try await actions.createItem(
                        title: title, note: note ?? "", in: CollectionID(rawValue: collection), request: AtlasRequest(request)
                    ).receipt
                case .appIntent:
                    let intent = CreateItemIntent()
                    intent.title = title
                    intent.note = note
                    intent.collection = LabCollectionEntity(try await actions.collection(CollectionID(rawValue: collection)))
                    intent.requestID = request.rawValue.uuidString
                    receipt = try await intent.run(with: link).receipt
                }
            case .updateItem(let request, let id, let expected, let title, let note):
                switch entryPoint {
                case .appUI:
                    receipt = try await actions.updateItem(
                        ItemID(rawValue: id), expected: try #require(Revision(rawValue: expected)),
                        title: title, note: note, request: AtlasRequest(request)
                    ).receipt
                case .appIntent:
                    let intent = UpdateItemIntent()
                    intent.item = try await entity(id, at: expected)
                    intent.newTitle = title
                    intent.newNote = note
                    intent.requestID = request.rawValue.uuidString
                    receipt = try await intent.run(with: link).receipt
                }
            case .archiveItem(let request, let id, let expected):
                let confirm: @Sendable (ArchivePrompt) async throws -> Void = approved.contains(step.id) ? spy.approve : spy.decline
                switch entryPoint {
                case .appUI:
                    try #require(approved.contains(step.id), "the app's archive is a control press the script approves")
                    receipt = try await actions.archiveItem(
                        ItemID(rawValue: id), expected: try #require(Revision(rawValue: expected)),
                        request: AtlasRequest(request), confirm: { _ in }
                    ).receipt
                case .appIntent:
                    let intent = ArchiveItemIntent()
                    intent.item = try await entity(id, at: expected)
                    intent.requestID = request.rawValue.uuidString
                    receipt = try await intent.run(with: link, confirm: confirm).receipt
                }
            case .undo(let request, let target):
                let offer = try #require(replay.receipts[target]?.undo, "step \(target) offered an undo")
                guard case .restoreItem(let id, let expected) = offer else {
                    Issue.record("Action Atlas has no action for the undo \(offer.kind.rawValue)")
                    throw ShowcaseFileError.unmappedUndo(step.id)
                }
                switch entryPoint {
                case .appUI:
                    receipt = try await actions.restoreItem(id, expected: expected, request: AtlasRequest(request)).receipt
                case .appIntent:
                    let intent = RestoreItemIntent()
                    intent.item = try await entity(id.rawValue, at: expected.rawValue)
                    intent.requestID = request.rawValue.uuidString
                    receipt = try await intent.run(with: link).receipt
                }
            case .find(let collection, let text, let includeArchived, let limit, _):
                switch entryPoint {
                case .appUI:
                    replay.reads[step.id] = try await actions.findItems(
                        text: text, in: collection.map(CollectionID.init(rawValue:)), includeArchived: includeArchived, limit: limit
                    ).map(\.id.rawValue)
                case .appIntent:
                    let intent = FindItemsIntent()
                    intent.text = text
                    intent.collection = try await collection.asyncMap { LabCollectionEntity(try await actions.collection(CollectionID(rawValue: $0))) }
                    intent.includeArchived = includeArchived
                    intent.limit = limit
                    replay.reads[step.id] = try await intent.run(with: link).value.map(\.id)
                }
                receipt = nil
            }
            if let receipt { replay.receipts[step.id] = receipt }
        }
        replay.confirmations = spy.prompts.withLock { $0.map(\.text) }
        return replay
    }
}

private extension Optional {
    func asyncMap<Mapped>(_ transform: (Wrapped) async throws -> Mapped) async rethrows -> Mapped? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}
