import ActionAtlas
import Foundation
import LabDomain
import LabStore
import Testing
@testable import NativeLab

/// LAB-001 in the sandboxed Mac host: Action Atlas through `LabLibrary`, `LabDataService`, and a
/// fresh SQLite store per library, never the app's real store.
@MainActor
@Suite struct ActionAtlasHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ActionAtlasHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func storeURL(_ name: String) throws -> URL {
        let directory = folder.appending(path: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: LabStoreLocation.fileName)
    }

    private func startedLibrary(_ name: String) async throws -> (LabLibrary, URL) {
        let url = try storeURL(name)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return (library, url)
    }

    private static let amber = ItemID(rawValue: UUID(uuidString: "DB666EF1-F642-43F1-B415-895B6ECFF693")!)
    private static let cobalt = ItemID(rawValue: UUID(uuidString: "9B97BF2F-4D0B-4197-9CA8-36489DF40455")!)

    /// Request IDs both runs share, so their new entities get the same IDs.
    private static func request(_ index: Int) -> AtlasRequest {
        AtlasRequest(RequestID(rawValue: UUID(uuidString: String(format: "A7A5A7A5-0000-4000-8000-%012d", index))!))
    }

    // MARK: UI and intent

    /// The same operation sequence through the app-UI path the action browser uses and through the
    /// App Intents, each on a fresh store, leaves identical persisted state. Excluded by design:
    /// operation IDs (random per commit) and the receipt's adapter (App UI or App Intent), plus the
    /// first-run Reset Demo receipt, whose request ID is random.
    @Test func uiAndIntentYieldIdenticalPersistedState() async throws {
        let (uiLibrary, uiURL) = try await startedLibrary("ui")
        let (intentLibrary, intentURL) = try await startedLibrary("intent")
        let requests = (1...7).map(Self.request)

        // Through the in-app action browser's path: ActionAtlasActions as the app UI.
        let ui = uiLibrary.atlasActions
        let uiCollection = try await ui.createCollection(title: "Field notes", request: requests[0]).entity
        let uiItem = try await ui.createItem(title: "Graphite stick", note: "Soft, 6B.", in: uiCollection.id, request: requests[1]).entity
        let uiFound = try await ui.findItems(text: "graphite")
        #expect(uiFound.map(\.id) == [uiItem.id])
        let uiUpdated = try await ui.updateItem(uiItem.id, expected: uiItem.revision, title: nil, note: "Soft, 6B. Smudges.", request: requests[2]).entity
        let uiArchived = try await ui.archiveItem(uiItem.id, expected: uiUpdated.revision, request: requests[3], confirm: { _ in }).entity
        _ = try await ui.restoreItem(uiItem.id, expected: uiArchived.revision, request: requests[4])
        _ = try await ui.updateItem(Self.amber, expected: .initial, title: "Amber swatch, matte", note: nil, request: requests[5])
        _ = try await ui.archiveItem(Self.cobalt, expected: .initial, request: requests[6], confirm: { _ in })
        let uiExport = try await ui.exportItem(uiItem.id, as: .json)

        // Through the App Intents, as Shortcuts would run them, with the system dialogs stood in.
        let link = ActionAtlasLink(backend: LibraryAtlasBackend(library: intentLibrary))
        let createCollection = CreateCollectionIntent()
        createCollection.title = "Field notes"
        createCollection.requestID = requests[0].id.description
        let collection = try await createCollection.run(with: link).value

        let createItem = CreateItemIntent()
        createItem.title = "Graphite stick"
        createItem.note = "Soft, 6B."
        createItem.collection = collection
        createItem.requestID = requests[1].id.description
        _ = try await createItem.run(with: link)

        let find = FindItemsIntent()
        find.text = "graphite"
        find.includeArchived = false
        find.limit = 20
        let found = try await find.run(with: link).value
        #expect(found.map(\.id) == [uiItem.id.rawValue])

        let update = UpdateItemIntent()
        update.item = found[0]
        update.newNote = "Soft, 6B. Smudges."
        update.requestID = requests[2].id.description
        let updated = try await update.run(with: link).value

        let archive = ArchiveItemIntent()
        archive.item = updated
        archive.requestID = requests[3].id.description
        let archived = try await archive.run(with: link) { _ in }.value

        let restore = RestoreItemIntent()
        restore.item = archived
        restore.requestID = requests[4].id.description
        _ = try await restore.run(with: link)

        let get = GetItemIntent()
        let amberEntity = try #require(try await LabItemQuery.lookUp(Self.amber, link: link))
        get.item = amberEntity
        let renameDemo = UpdateItemIntent()
        renameDemo.item = try await get.run(with: link).value
        renameDemo.newTitle = "Amber swatch, matte"
        renameDemo.requestID = requests[5].id.description
        _ = try await renameDemo.run(with: link)

        let archiveDemo = ArchiveItemIntent()
        archiveDemo.item = try #require(try await LabItemQuery.lookUp(Self.cobalt, link: link))
        archiveDemo.requestID = requests[6].id.description
        _ = try await archiveDemo.run(with: link) { _ in }

        let export = ExportItemIntent()
        export.item = try #require(try await LabItemQuery.lookUp(uiItem.id, link: link))
        export.format = .json
        let intentExport = try await export.run(with: link).value

        // Persisted state, read back from each store file.
        let uiStore = try await SQLiteOperationStore(url: uiURL)
        let intentStore = try await SQLiteOperationStore(url: intentURL)
        let byID: (LabCollection, LabCollection) -> Bool = { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        let itemsByID: (LabItem, LabItem) -> Bool = { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        let uiCollections = try await uiStore.collections().sorted(by: byID)
        let uiItems = try await uiStore.items(in: nil).sorted(by: itemsByID)
        #expect(uiCollections.count == 4 && uiItems.count == 13)
        #expect(try await intentStore.collections().sorted(by: byID) == uiCollections)
        #expect(try await intentStore.items(in: nil).sorted(by: itemsByID) == uiItems)

        for request in requests {
            let fromUI = try #require(try await uiStore.receipt(for: request.id))
            let fromIntent = try #require(try await intentStore.receipt(for: request.id))
            #expect(fromUI.admitted.adapter == .appUI)
            #expect(fromIntent.admitted.adapter == .appIntent)
            #expect(fromIntent.operationID != fromUI.operationID)
            #expect(fromIntent.admitted.operation == fromUI.admitted.operation)
            #expect(fromIntent.status == fromUI.status)
            #expect(fromIntent.changes == fromUI.changes)
            #expect(fromIntent.removed == fromUI.removed)
            #expect(fromIntent.summary == fromUI.summary)
            #expect(fromIntent.undo == fromUI.undo)
        }
        #expect(intentExport.data == uiExport.data, "the same state exports to the same bytes")

        // Both sessions list the receipts for the inspector, each naming its entry point.
        #expect(uiLibrary.receipts.prefix(7).allSatisfy { ReceiptPresentation($0).adapter == "App UI" })
        #expect(intentLibrary.receipts.prefix(7).allSatisfy { ReceiptPresentation($0).adapter == "App Intent" })
    }

    // MARK: Grants

    @Test func theHostRefusesAnIntentArchiveWithoutTheSystemConfirmation() async throws {
        let (library, _) = try await startedLibrary("no-confirmation")
        let listed = library.receipts.count
        let service = try await library.openedService()
        let archive = DomainOperation.archiveItem(id: Self.amber, expected: .initial)
        let requestID = RequestID()

        await #expect(throws: OperationError.self) {
            try await service.perform(archive, requestID: requestID, authority: .intent(nil))
        }
        let backend = LibraryAtlasBackend(library: library)
        let error = await #expect(throws: ActionAtlasError.self) {
            try await backend.commit(archive, requestID: RequestID(), authority: .intent(nil), names: [:])
        }
        #expect(error?.message == "Archiving from Shortcuts or Siri needs your confirmation, and none was given. Nothing was changed.")
        #expect(try await service.item(Self.amber, as: LabDataService.appIntent).isArchived == false)
        #expect(library.receipts.count == listed, "a refused commit records no receipt")
        #expect(try await library.openedService().item(Self.amber, as: LabDataService.appUI).revision == .initial)
    }

    @Test func theConfirmedIntentArchiveCommitsAndItsReceiptOffersAnUndoInTheApp() async throws {
        let (library, _) = try await startedLibrary("confirmed")
        let link = ActionAtlasLink(backend: LibraryAtlasBackend(library: library))
        let archive = ArchiveItemIntent()
        archive.item = try #require(try await LabItemQuery.lookUp(Self.amber, link: link))
        let asked = Asked()
        let output = try await archive.run(with: link) { prompt in await asked.record(prompt.text) }

        #expect(await asked.prompts == ["Archive “Amber swatch”? It leaves normal view without being deleted, and its receipt in Native Lab offers an undo."])
        #expect(output.value.isArchived)
        #expect(output.dialog == "Archived item “Amber swatch”. Its receipt in Native Lab offers an undo.")

        // The receipt inspector reads this list; the intent's receipt is first, with its undo.
        let record = try #require(library.latestReceipt)
        #expect(record.receipt == output.receipt)
        let presentation = ReceiptPresentation(record)
        #expect(presentation.adapter == "App Intent")
        #expect(presentation.operation == "Archive Item")
        #expect(presentation.undo?.title == "Restore Item “Amber swatch”")
        #expect(presentation.undo?.expectedRevision == "Expects revision 2")
        #expect(library.item(id: Self.amber)?.isArchived == true, "the collection browser sees the change")

        // Undo from the inspector runs as the app UI.
        let undo = try #require(await library.undo(record))
        #expect(ReceiptPresentation(undo).adapter == "App UI")
        #expect(library.item(id: Self.amber)?.isArchived == false)
    }

    // MARK: Duplicates, unavailable store, metadata

    @Test func aRepeatedIntentRequestCommitsOnceAndIsListedOnce() async throws {
        let (library, url) = try await startedLibrary("duplicate")
        let link = ActionAtlasLink(backend: LibraryAtlasBackend(library: library))
        let intent = CreateCollectionIntent()
        intent.title = "Field notes"
        intent.requestID = Self.request(1).id.description
        let first = try await intent.run(with: link)
        let second = try await intent.run(with: link)

        #expect(first.receipt == second.receipt)
        #expect(library.receipts.count(where: { $0.receipt.requestID == Self.request(1).id }) == 1)
        let store = try await SQLiteOperationStore(url: url)
        #expect(try await store.collections().count(where: { $0.namespace == .user }) == 1)
        #expect(library.census?.user == NamespaceCount(collections: 1, items: 0, archived: 0))
    }

    @Test func aStoreThatCannotOpenMakesEveryIntentUnavailable() async throws {
        let url = try storeURL("garbage")
        let garbage = Data("not a database, just some bytes".utf8)
        try garbage.write(to: url)
        let library = LabLibrary(locateStore: { url })
        let link = ActionAtlasLink(backend: LibraryAtlasBackend(library: library))
        let find = FindItemsIntent()
        find.includeArchived = false
        find.limit = 20

        let error = await #expect(throws: ActionAtlasError.self) { try await find.run(with: link) }
        guard case .unavailable(let reason)? = error else {
            Issue.record("expected the unavailable path, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("left unchanged"))
        #expect(try Data(contentsOf: url) == garbage)
    }

    @Test func theActionBrowserListsOneActionPerIntentAndIsRestorable() {
        #expect(AtlasAction.allCases.map(\.title) == [
            "Create Lab Collection", "Create Lab Item", "Find Lab Items", "Get Lab Item",
            "Update Lab Item", "Archive Lab Item", "Restore Lab Item", "Export Lab Item",
        ])
        #expect(SidebarDestination(storageKey: SidebarDestination.actionAtlas.storageKey) == .actionAtlas)
        #expect(AtlasAction.matching("archive") == [.archiveItem, .restoreItem])
    }

    @Test func theBuiltAppCarriesTheActionAtlasIntentMetadata() throws {
        let url = try #require(Bundle.main.url(forResource: "extract", withExtension: "actionsdata", subdirectory: "Metadata.appintents"))
        let metadata = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let actions = try #require(metadata["actions"] as? [String: [String: Any]])
        func intents(from module: String) -> Set<String> {
            Set(actions.filter { ($0.value["fullyQualifiedTypeName"] as? String)?.hasPrefix(module + ".") == true }.keys)
        }
        #expect(intents(from: "ActionAtlas") == [
            "CreateCollectionIntent", "CreateItemIntent", "FindItemsIntent", "GetItemIntent",
            "UpdateItemIntent", "ArchiveItemIntent", "RestoreItemIntent", "ExportItemIntent",
        ])
        // LAB-004 Surface Deck's toggle, read, and launch action join them.
        #expect(intents(from: "SurfaceDeck") == ["SetDemoSessionIntent", "GetDemoSessionIntent", "OpenSurfaceDeckIntent"])
        // LAB-042: the one allowlisted desktop command. It is Mac-only.
        #expect(intents(from: "DesktopNativePower") == ["RunDesktopCommandIntent"])
        // LAB-002 Context Cards' ask and set-aside. Neither is a curated App Shortcut.
        #expect(intents(from: "ContextCards") == ["AskAboutVisibleSampleIntent", "SetAsideSampleIntent"])
        #expect(actions.count == 14)
        let entities = try #require(metadata["entities"] as? [String: Any])
        #expect(Set(entities.keys) == ["LabItemEntity", "LabCollectionEntity"])
        let queries = try #require(metadata["queries"] as? [String: Any])
        #expect(Set(queries.keys) == ["LabItemQuery", "LabCollectionQuery"])
    }
}

extension LabItemQuery {
    /// One item as the system would resolve a stored reference, through the given link.
    static func lookUp(_ id: ItemID, link: ActionAtlasLink) async throws -> LabItemEntity? {
        let actions = link.actions(.appIntent)
        guard let item = try await actions.items(ids: [id]).first else { return nil }
        let titles = try await actions.collectionTitles(for: [item])
        return LabItemEntity(item, collectionTitle: titles[item.collectionID])
    }
}

private actor Asked {
    private(set) var prompts: [String] = []

    func record(_ prompt: String) { prompts.append(prompt) }
}
