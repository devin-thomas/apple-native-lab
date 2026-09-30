import AppKit
import CoreTransferable
import Foundation
import LabDomain
import PortableObjects
import Testing
import UniformTypeIdentifiers
@testable import NativeLab

/// LAB-008 in the sandboxed Mac host: Portable Objects through `PortableObjectsSession`,
/// `LabLibrary`, `LabDataService`, and a fresh SQLite store and staging folder per library, never
/// the app's real ones.
@MainActor
@Suite struct PortableObjectsHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "PortableObjectsHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private struct Lab {
        let library: LabLibrary
        let collection: CollectionID

        @MainActor
        func session(_ name: String, in folder: URL) -> PortableObjectsSession {
            let staging = folder.appending(path: "staging-\(name)", directoryHint: .isDirectory)
            return PortableObjectsSession(locateStaging: { staging })
        }
    }

    /// A started library on its own store, with one collection of the person's own.
    private func lab(_ name: String) async throws -> Lab {
        let directory = folder.appending(path: name)
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
        return Lab(library: library, collection: collection)
    }

    private static let sampleID = ItemID(rawValue: UUID(uuidString: "F1586771-0F15-4044-A372-5F9BC9968FDB")!)

    // MARK: The declared type

    @Test func theAppDeclaresTheLabObjectTypeFromItsBundlePrefix() throws {
        let declared = try #require(Bundle.main.object(forInfoDictionaryKey: LabObjectType.infoPlistKey) as? String)
        #expect(declared.hasSuffix(".nativelab.object") && !declared.contains("$("))
        #expect(LabObjectType.identifier == declared)
        let exported = try #require(Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]])
        #expect(exported.first?["UTTypeIdentifier"] as? String == declared)
        #expect(UTType.labObject.identifier == declared)
        #expect(UTType.labObject.conforms(to: .json))
        #expect(UTType.labObject.preferredFilenameExtension == "anlab")
        // Other builds on the same Mac (another bundle prefix) may also register `.anlab`, so check that
        // this app's type is among the registered ones rather than the only one.
        #expect(UTType.types(tag: "anlab", tagClass: .filenameExtension, conformingTo: nil).contains(.labObject))
    }

    // MARK: Import through the host

    @Test func theSampleImportsThroughStagingWithAReceiptInTheSessionList() async throws {
        let lab = try await lab("sample")
        let session = lab.session("sample", in: folder)
        await session.load(lab.library)
        #expect(session.destinations.map(\.id) == [lab.collection])
        #expect(session.destinationID == lab.collection)

        await session.openSample(library: lab.library)
        let review = try #require(session.review)
        guard case .create = review.plan else {
            Issue.record("expected a new object")
            return
        }
        let before = lab.library.receipts.count
        let record = try #require(await session.commit(library: lab.library))
        #expect(record.receipt.status == .committed)
        #expect(record.receipt.admitted.adapter == .appUI)
        #expect(record.receipt.affectedEntities == [.item(Self.sampleID)])
        #expect(lab.library.receipts.count == before + 1)
        #expect(lab.library.latestReceipt?.id == record.id)
        #expect(session.review == nil && session.message == nil)
        #expect(session.outcome?.sentence.hasPrefix("Imported") == true)
        #expect(session.entry(Self.sampleID)?.collection?.id == lab.collection)

        // Opening it again finds it by identity and adds nothing.
        await session.openSample(library: lab.library)
        let again = try #require(session.review)
        guard case .alreadyPresent = again.plan else {
            Issue.record("expected the object to be recognized")
            return
        }
        #expect(await session.commit(library: lab.library) == nil)
        #expect(session.message == PortableObjectError.nothingToImport.userMessage)
        #expect(lab.library.receipts.count == before + 1)
        await session.closeReview()
    }

    /// Export from one Mac store, import into a fresh one, export again: the same bytes, through
    /// SQLite on both sides, with unknown fields, extras, the Unicode title, and the empty note.
    @Test func aRoundTripThroughTwoSQLiteStoresReturnsTheSameDocument() async throws {
        let sample = try #require(PortableSample.data)
        let first = try await lab("first")
        let firstSession = first.session("first", in: folder)
        await firstSession.load(first.library)
        await firstSession.openSample(library: first.library)
        _ = try #require(await firstSession.commit(library: first.library))
        let exported = try #require(firstSession.exportPreview(for: Self.sampleID)).object.data
        #expect(exported == sample)

        let second = try await lab("second")
        let secondSession = second.session("second", in: folder)
        await secondSession.load(second.library)
        let file = folder.appending(path: "exported.anlab")
        try exported.write(to: file)
        await secondSession.open(fileAt: file, library: second.library)
        _ = try #require(await secondSession.commit(library: second.library))
        #expect(try #require(secondSession.exportPreview(for: Self.sampleID)).object.data == sample)
    }

    // MARK: Two windows

    /// A drag from one window to another at the data level: the row's object goes through an item
    /// provider, the way a drag carries it, and the other window's session receives it.
    @Test func anObjectDraggedToAnotherWindowIsRecognizedByItsIdentity() async throws {
        let lab = try await lab("windows")
        let source = lab.session("source", in: folder)
        let destination = lab.session("destination", in: folder)
        await source.load(lab.library)
        await destination.load(lab.library)

        let entry = try #require(source.entries.first { $0.item.namespace == .demo })
        let object = try #require(source.portableObject(for: entry))
        let provider = NSItemProvider()
        provider.register(object)
        let incoming: IncomingObject = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: IncomingObject.self) { continuation.resume(with: $0) }
        }
        let receiptsBefore = lab.library.receipts.count
        await destination.receive([incoming], library: lab.library)
        let review = try #require(destination.review)
        #expect(review.document.itemID == entry.item.id)
        #expect(review.plan == .alreadyPresent(stored: entry.item))
        #expect(lab.library.receipts.count == receiptsBefore)
        await destination.closeReview()
    }

    // MARK: Unavailable

    /// A store that cannot open makes every import say so, and nothing is staged.
    @Test func withoutAStoreAnImportSaysTheLabIsUnavailable() async throws {
        struct NoStore: Error {}
        let library = LabLibrary(locateStore: { throw NoStore() })
        let staging = folder.appending(path: "staging-unavailable", directoryHint: .isDirectory)
        let session = PortableObjectsSession(locateStaging: { staging })
        await session.load(library)
        #expect(session.groups.isEmpty)
        await session.openSample(library: library)
        #expect(session.review == nil)
        #expect(session.message == PortableObjectError.unavailable.userMessage)
        #expect(library.receipts.isEmpty)
    }

    // MARK: Refusals

    @Test func anOversizedDropAndAMalformedFileAreRefusedWithReadableReasons() async throws {
        let lab = try await lab("refusals")
        let session = lab.session("refusals", in: folder)
        await session.load(lab.library)
        let receiptsBefore = lab.library.receipts.count

        let oversized = Data(repeating: 0x20, count: IncomingObject.maximumBytes + 1)
        let incoming = try await IncomingObject(importing: oversized, contentType: .labObject)
        await session.receive([incoming], library: lab.library)
        #expect(session.review == nil)
        #expect(session.message == "The document is larger than 2 MB, the most a lab object can be. Nothing was imported.")

        let malformed = folder.appending(path: "malformed.anlab")
        try Data(#"{"format": "native-lab-object", "title": "cut off"#.utf8).write(to: malformed)
        await session.open(fileAt: malformed, library: lab.library)
        #expect(session.review == nil)
        #expect(session.message == "The document is not valid JSON, so it was refused. Nothing was imported.")

        let traversal = folder.appending(path: "traversal.anlab")
        let document = #"{"format":"native-lab-object","schemaVersion":1,"documentID":"\#(UUID().uuidString)","kind":"collection-item","title":"T","attachments":[{"path":"../x","byteCount":1,"sha256":"\#(String(repeating: "0", count: 64))"}]}"#
        try Data(document.utf8).write(to: traversal)
        await session.open(fileAt: traversal, library: lab.library)
        #expect(session.review == nil)
        #expect(session.message?.hasPrefix("Attachment 1 has a path that points outside the object") == true)

        #expect(lab.library.receipts.count == receiptsBefore)
    }
}
