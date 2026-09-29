import ActionAtlas
import Foundation
import LabDomain
import LabStore
import Testing
@testable import NativeLab

/// LAB-001-B step 3 in the sandboxed Mac host: denial, cancellation, stale and duplicate state,
/// and Reset Demo beside imported user data, through `LabLibrary`, `LabDataService`, and a fresh
/// SQLite store per test, never the app's real store. They add to `ActionAtlasHostTests`
/// (LAB-001-A).
@MainActor
@Suite struct ActionAtlasQualificationHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ActionAtlasQualificationHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func startedLibrary() async throws -> (LabLibrary, URL) {
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return (library, url)
    }

    private static let amber = ItemID(rawValue: UUID(uuidString: "DB666EF1-F642-43F1-B415-895B6ECFF693")!)
    private static let cobalt = ItemID(rawValue: UUID(uuidString: "9B97BF2F-4D0B-4197-9CA8-36489DF40455")!)
    private static let pigments = CollectionID(rawValue: UUID(uuidString: "A40194B3-5E91-4C5C-AE02-CF703BE23224")!)

    private static func request(_ index: Int) -> AtlasRequest {
        AtlasRequest(RequestID(rawValue: UUID(uuidString: String(format: "B1B1B1B1-0000-4000-8000-%012d", index))!))
    }

    // MARK: Cancellation and denial

    @Test func aDeclinedIntentConfirmationLeavesNoReceiptInTheStoreOrTheSession() async throws {
        let (library, url) = try await startedLibrary()
        let listed = library.receipts.count
        let link = ActionAtlasLink(backend: LibraryAtlasBackend(library: library))
        let archive = ArchiveItemIntent()
        archive.item = try #require(try await LabItemQuery.lookUp(Self.amber, link: link))
        archive.requestID = Self.request(1).id.description

        await #expect(throws: CancellationError.self) {
            try await archive.run(with: link) { _ in throw CancellationError() }
        }
        #expect(library.receipts.count == listed, "nothing for the inspector to show")
        let store = try await SQLiteOperationStore(url: url)
        #expect(try await store.receipt(for: Self.request(1).id) == nil)
        #expect(try await store.item(Self.amber)?.isArchived == false)

        // Confirmed later under the same request, it commits once and is listed once.
        let confirmed = try await archive.run(with: link) { _ in }
        #expect(confirmed.value.isArchived)
        #expect(library.receipts.count(where: { $0.receipt.requestID == Self.request(1).id }) == 1)
    }

    @Test func aRequestIDFromTheOtherEntryPointIsRefusedInTheHost() async throws {
        let (library, url) = try await startedLibrary()
        _ = try await library.atlasActions.createCollection(title: "Field notes", request: Self.request(1))

        let link = ActionAtlasLink(backend: LibraryAtlasBackend(library: library))
        let intent = CreateCollectionIntent()
        intent.title = "Field notes"
        intent.requestID = Self.request(1).id.description
        let error = await #expect(throws: ActionAtlasError.self) { try await intent.run(with: link) }
        #expect(error == .refused(.requestIDReused(Self.request(1).id)))

        let store = try await SQLiteOperationStore(url: url)
        #expect(try await store.collections().count(where: { $0.namespace == .user }) == 1)
        #expect(try await store.receipt(for: Self.request(1).id)?.admitted.adapter == .appUI)
        #expect(library.receipts.count(where: { $0.receipt.requestID == Self.request(1).id }) == 1)
    }

    // MARK: Stale state

    /// The intent's snapshot was taken before the action browser changed the item. The intent's
    /// update is not applied, its conflict receipt is what the inspector shows, and the browser's
    /// change stands in the store.
    @Test func aStaleIntentSnapshotConflictsAndTheInspectorShowsIt() async throws {
        let (library, url) = try await startedLibrary()
        let link = ActionAtlasLink(backend: LibraryAtlasBackend(library: library))
        let snapshot = try #require(try await LabItemQuery.lookUp(Self.amber, link: link))
        _ = try await library.atlasActions.updateItem(
            Self.amber, expected: .initial, title: "Amber swatch, matte", note: nil, request: Self.request(1)
        )

        let update = UpdateItemIntent()
        update.item = snapshot
        update.newTitle = "Amber swatch, gloss"
        update.requestID = Self.request(2).id.description
        let error = await #expect(throws: ActionAtlasError.self) { try await update.run(with: link) }
        #expect(error?.message.hasPrefix("Not applied: the item changed after it was picked (expected revision 1, found 2).") == true)

        let latest = try #require(library.latestReceipt)
        let presentation = ReceiptPresentation(latest)
        #expect(latest.receipt.requestID == Self.request(2).id)
        #expect(presentation.adapter == "App Intent")
        #expect(!presentation.isCommitted)
        #expect(presentation.status == "Not applied: expected revision 1, found 2")
        #expect(presentation.noUndoReason == "Nothing changed, so there is nothing to undo.")
        let store = try await SQLiteOperationStore(url: url)
        let amber = try #require(try await store.item(Self.amber))
        #expect(amber.title.value == "Amber swatch, matte" && amber.revision.rawValue == 2)
    }

    // MARK: Reset Demo and imported user data

    /// Reset Demo from the app restores the samples the intents changed and leaves the person's
    /// data alone: the intents' own collection and item, and an item imported by a second
    /// connection to the same store file, as the share extension will write it.
    @Test func resetDemoLeavesIntentCreatedAndImportedDataUntouched() async throws {
        let (library, url) = try await startedLibrary()
        let link = ActionAtlasLink(backend: LibraryAtlasBackend(library: library))
        let intents = link.actions(.appIntent)
        let notes = try await intents.createCollection(title: "Field notes", request: Self.request(1)).entity
        _ = try await intents.createItem(title: "Graphite stick", note: "Soft, 6B.", in: notes.id, request: Self.request(2))

        // The import: another connection, its own service and grant ledger, the share
        // extension's adapter, and a grant for exactly one new item in the chosen collection.
        let extensionStore = try await SQLiteOperationStore(url: url)
        let ledger = GrantLedger()
        let extensionService = OperationService(store: extensionStore, policy: GrantAuthorizationPolicy(ledger: ledger))
        let inbox = InMemoryStagingInbox()
        let staged = await inbox.stage(try StagingRecord.text(utf8: Array("Harbor walk\nBring the blue notebook.".utf8)))
        try ledger.issue(to: .shareExtension, for: [.createItem], on: ImportAdopter.grantTarget(into: notes.id))
        let imported = try await ImportAdopter(service: extensionService, inbox: inbox, ledger: ledger).adopt(staged.id, into: notes.id)
        #expect(imported.receipt.admitted.adapter == .shareExtension)

        // The intents change two samples; the archive is confirmed.
        let amber = try #require(try await LabItemQuery.lookUp(Self.amber, link: link))
        let rename = UpdateItemIntent()
        rename.item = amber
        rename.newTitle = "Amber swatch, matte"
        _ = try await rename.run(with: link)
        let archive = ArchiveItemIntent()
        archive.item = try #require(try await LabItemQuery.lookUp(Self.cobalt, link: link))
        let archived = try await archive.run(with: link) { _ in }
        let archiveReceipt = try #require(archived.receipt)
        let archiveRecord = try #require(library.receipt(id: archiveReceipt.operationID))

        let reader = try await SQLiteOperationStore(url: url)
        func userState() async throws -> ([LabCollection], [LabItem]) {
            (
                try await reader.collections().filter { $0.namespace == .user }.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString },
                try await reader.items(in: nil).filter { $0.namespace == .user }.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
            )
        }
        let before = try await userState()
        #expect(before.0.count == 1 && before.1.count == 2)

        // Reset Demo, as the person confirms it in the app.
        let reset = try #require(await library.resetDemo())
        let presentation = ReceiptPresentation(reset)
        #expect(presentation.summary == "Reset the demo to its original 3 collections and 12 items: restored 2.")
        #expect(Set(reset.receipt.changes.map(\.entity)) == [.item(Self.amber), .item(Self.cobalt)])
        #expect(reset.receipt.removed.isEmpty)

        let after = try await userState()
        #expect(after.0 == before.0)
        #expect(after.1 == before.1)
        #expect(try await reader.receipt(for: imported.receipt.requestID) == imported.receipt)
        #expect(library.census?.user == NamespaceCount(collections: 1, items: 2, archived: 0))
        #expect(library.item(id: Self.amber)?.title.value == "Amber swatch")
        #expect(library.item(id: Self.cobalt)?.isArchived == false)

        // The intent's archive offered an undo pinned to revision 2; after the reset it is stale.
        let undo = try #require(await library.undo(archiveRecord))
        #expect(ReceiptPresentation(undo).status == "Not applied: expected revision 2, found 3")

        // An import cannot land in a demo collection, where a reset could reach it.
        let demoStaged = await inbox.stage(try StagingRecord.text(utf8: Array("Tide table".utf8)))
        try ledger.issue(to: .shareExtension, for: [.createItem], on: ImportAdopter.grantTarget(into: Self.pigments))
        await #expect(throws: ImportRejection.destinationUnavailable) {
            try await ImportAdopter(service: extensionService, inbox: inbox, ledger: ledger).adopt(demoStaged.id, into: Self.pigments)
        }
    }
}
