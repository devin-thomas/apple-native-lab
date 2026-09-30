import Foundation
import LabDomain
import ShareIngress
import Testing
@testable import NativeLab

/// LAB-007 in the sandboxed Mac host: the share inbox's paste and file-picker fallbacks stage into
/// the host's folder, and Add commits through `LabLibrary`, `LabDataService`, `ImportAdopter`, and
/// the one `OperationService`, with a receipt. Each test uses a fresh store and fresh folders in
/// the app container's temporary folder, never the app's real store or inbox.
@MainActor
@Suite struct ShareInboxHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ShareInboxHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func started(sharedRoot: URL? = nil) async throws -> (LabLibrary, ShareInboxModel) {
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let hostRoot = folder.appending(path: "Share Inbox")
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let inbox = ShareInboxModel(locateHost: { hostRoot }, sharedRoot: sharedRoot)
        await inbox.start()
        try #require(inbox.phase == .ready)
        return (library, inbox)
    }

    private static let injection: String = {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/hostile/prompt-injection.txt")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    // MARK: The fallback, end to end

    @Test func aPastedNoteIsAddedThroughTheOperationServiceWithAReceipt() async throws {
        let (library, inbox) = try await started()
        #expect(inbox.shareSheet == .notInThisBuild, "the CoreLocal Mac declares no App Group")

        inbox.paste([NSItemProvider(object: "Harbor walk\nBring the blue notebook." as NSString)])
        await inbox.waitForIntake()
        #expect(inbox.lastReport?.summary == "1 item is waiting for review.")
        let entry = try #require(inbox.snapshot.entries.first)
        #expect(entry.source == .host && entry.origin?.surface == .paste)
        #expect(entry.adoptability == .ready)

        // Demo collections are never offered; the person creates their own first.
        await inbox.loadCollections(from: library)
        #expect(inbox.collections.isEmpty)
        #expect(await inbox.createCollection(titled: "Field notes", in: library))
        let collection = try #require(inbox.collections.first)
        #expect(inbox.destinationID == collection.id)

        let receiptsBefore = library.receipts.count
        let added = try #require(await inbox.add(entry, to: collection.id, in: library))
        #expect(!added.isDuplicate)
        #expect(added.collectionTitle == "Field notes")
        let presentation = ReceiptPresentation(added.record)
        #expect(presentation.operation == "Create Item")
        #expect(presentation.adapter == "App UI")
        #expect(presentation.isCommitted)
        #expect(presentation.changes.map(\.name) == ["Harbor walk"])
        #expect(library.receipts.count == receiptsBefore + 1)
        #expect(library.latestReceipt == added.record)

        // The import left the inbox, and the item is in the person's own data.
        #expect(inbox.snapshot.entries.isEmpty)
        #expect(inbox.added[entry.id]?.entry == entry)
        #expect(library.census?.user == NamespaceCount(collections: 1, items: 1, archived: 0))
        #expect(library.census?.demo == NamespaceCount(collections: 3, items: 12, archived: 0))
    }

    @Test func chosenFilesWaitForReviewButCannotBeAddedYet() async throws {
        let (_, inbox) = try await started()
        let file = folder.appending(path: "Tide notes.txt")
        try Data("High water at noon.".utf8).write(to: file)
        inbox.importFiles([file])
        await inbox.waitForIntake()
        let entry = try #require(inbox.snapshot.entries.first)
        #expect(entry.origin?.surface == .filePicker)
        #expect(entry.content == .files([InboxFile(name: "Tide notes.txt", byteCount: 19)]))
        #expect(entry.adoptability == .unavailable(.attachmentsNotAdoptable))

        await inbox.discard(entry)
        #expect(inbox.snapshot.entries.isEmpty)
    }

    // MARK: The share extension's folder

    @Test func sharedContentIsAddedAsTheShareExtension() async throws {
        let sharedRoot = folder.appending(path: "group")
        let (library, inbox) = try await started(sharedRoot: sharedRoot)
        let extensionSide = IngressStation(area: try IngressArea(source: .shareExtension, root: sharedRoot))
        let item = NSExtensionItem()
        item.attributedContentText = NSAttributedString(string: "Tide tables")
        item.attachments = [NSItemProvider(object: URL(string: "https://example.org/tides")! as NSURL)]
        let report = await extensionSide.receive(ItemProviderAttachment.attachments(from: [item]), via: .shareExtension)
        #expect(report.stagedCount == 1)

        await inbox.refresh()
        let entry = try #require(inbox.snapshot.entries.first)
        #expect(entry.source == .shareExtension)
        #expect(await inbox.createCollection(titled: "Reading list", in: library))
        let destination = try #require(inbox.destinationID)
        let added = try #require(await inbox.add(entry, to: destination, in: library))
        let presentation = ReceiptPresentation(added.record)
        #expect(presentation.adapter == "Share extension")
        #expect(presentation.changes.map(\.name) == ["Tide tables"])
    }

    @Test func instructionLikeSharedTextIsAddedOnlyAsANote() async throws {
        try #require(!Self.injection.isEmpty)
        let sharedRoot = folder.appending(path: "group")
        let (library, inbox) = try await started(sharedRoot: sharedRoot)
        let extensionSide = IngressStation(area: try IngressArea(source: .shareExtension, root: sharedRoot))
        _ = await extensionSide.receive(
            ItemProviderAttachment.attachments(from: [NSItemProvider(object: Self.injection as NSString)]), via: .shareExtension
        )
        await inbox.refresh()
        let entry = try #require(inbox.snapshot.entries.first)
        #expect(await inbox.createCollection(titled: "Inbox", in: library))
        let receiptsBefore = library.receipts.count

        let destination = try #require(inbox.destinationID)
        let added = try #require(await inbox.add(entry, to: destination, in: library))
        #expect(added.record.receipt.admitted.operation.kind == .createItem)
        #expect(added.record.receipt.changes.count == 1)
        #expect(library.receipts.count == receiptsBefore + 1)
        // The demo is untouched: nothing archived, nothing reset, nothing removed.
        #expect(library.census?.demo == NamespaceCount(collections: 3, items: 12, archived: 0))
        #expect(library.census?.user == NamespaceCount(collections: 1, items: 1, archived: 0))
        guard case .createItem(let draft) = added.record.receipt.admitted.operation else { return }
        #expect(draft.note.value == Self.injection)
    }

    @Test func addingTheSameContentAgainReturnsTheOriginalReceiptListedOnce() async throws {
        let (library, inbox) = try await started()
        #expect(await inbox.createCollection(titled: "Notes", in: library))
        let collection = try #require(inbox.destinationID)
        inbox.paste([NSItemProvider(object: "Twice pasted" as NSString)])
        await inbox.waitForIntake()
        let firstEntry = try #require(inbox.snapshot.entries.first)
        let first = try #require(await inbox.add(firstEntry, to: collection, in: library))
        let count = library.receipts.count

        inbox.paste([NSItemProvider(object: "Twice pasted" as NSString)])
        await inbox.waitForIntake()
        let secondEntry = try #require(inbox.snapshot.entries.first)
        let second = try #require(await inbox.add(secondEntry, to: collection, in: library))
        #expect(second.isDuplicate && !first.isDuplicate)
        #expect(second.record == first.record)
        #expect(library.receipts.count == count)
        #expect(library.census?.user.items == 1)
    }

    @Test func aDemoCollectionCannotTakeAnImport() async throws {
        let (library, inbox) = try await started()
        inbox.paste([NSItemProvider(object: "Not for the demo" as NSString)])
        await inbox.waitForIntake()
        let entry = try #require(inbox.snapshot.entries.first)
        let demo = try #require(library.collections.first?.collection.id)
        #expect(await inbox.add(entry, to: demo, in: library) == nil)
        #expect(inbox.failure == ImportRejection.destinationUnavailable.userMessage)
        #expect(inbox.snapshot.entries.count == 1, "the import keeps waiting")
        #expect(library.census?.demo == NamespaceCount(collections: 3, items: 12, archived: 0))
    }

    @Test func inboxRowsReadWithCommasNotMiddleDots() async throws {
        let (_, inbox) = try await started()
        inbox.paste([NSItemProvider(object: "Tide notes" as NSString), NSItemProvider(object: "Gull count" as NSString)])
        await inbox.waitForIntake()
        let spoken = inbox.snapshot.entries.map(\.spokenDescription)
        #expect(spoken.count == 2)
        #expect(spoken.allSatisfy { !$0.contains("·") })
        #expect(spoken.first?.hasPrefix("Tide notes, Text, Paste, 1 of 2, ") == true)
    }

    @Test func theShareInboxIsASidebarDestination() {
        #expect(SidebarDestination(storageKey: SidebarDestination.shareInbox.storageKey) == .shareInbox)
        #expect(SidebarDestination.shareInbox.title == "Share Inbox")
    }
}
