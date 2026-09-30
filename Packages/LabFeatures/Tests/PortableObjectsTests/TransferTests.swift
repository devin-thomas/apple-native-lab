import CoreTransferable
import Foundation
import LabDomain
import Testing
import UniformTypeIdentifiers
@testable import PortableObjects

/// The Transferable adapters: what a drag, a share, or a file export carries, and what a drop
/// accepts. They move bytes only; importing still goes through staging and review.
@Suite struct TransferTests {
    private var object: PortableObject {
        get throws { PortableObject(document: try LabDocument(decoding: try Fixture.sample)) }
    }

    /// Outside an app nothing declares the type, so only its identifier is known here. The Mac
    /// host test checks the declared type: its extension and its conformance to JSON.
    @Test func outsideAnAppTheLabObjectTypeUsesTheDefaultIdentifier() {
        #expect(LabObjectType.identifier == LabObjectType.defaultIdentifier)
        #expect(UTType.labObject.identifier == "org.example.nativelab.object")
    }

    @Test func representationsComeInOrderOfFidelity() throws {
        // The native document comes first, as a file and as data, then JSON, then text.
        #expect(PortableObject.exportedContentTypes() == [.labObject, .labObject, .json, .utf8PlainText])
        let descriptors = RepresentationDescriptor.all(for: try object.document)
        #expect(descriptors.map(\.kind) == [.nativeDocument, .json, .plainText, .url])
        #expect(descriptors.map(\.fidelity).prefix(3) == [.complete, .complete, .lossy])
        guard case .notOffered = descriptors[3].fidelity else {
            Issue.record("a link is not offered in this build")
            return
        }
    }

    @Test func theNativeDocumentAndJSONAreTheSameCompleteBytes() async throws {
        let object = try object
        let sample = try Fixture.sample
        #expect(try await object.exported(as: .labObject) == sample)
        #expect(try await object.exported(as: .json) == sample)
        let text = try await object.exported(as: .utf8PlainText)
        #expect(String(decoding: text, as: UTF8.self) == object.document.plainText)
    }

    @Test func aFileManagerGetsTheDocumentAsANamedFile() async throws {
        let object = try object
        let folder = FileManager.default.temporaryDirectory.appending(path: "TransferTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try await object.export(to: folder, contentType: .labObject)
        #expect(file.lastPathComponent == object.fileName(.nativeDocument))
        #expect(try Data(contentsOf: file) == object.data)
    }

    @Test func exportsSuggestAFileNameFromTheTitle() throws {
        let object = try object
        #expect(object.fileName(.nativeDocument).hasSuffix(".anlab"))
        #expect(object.fileName(.nativeDocument).hasPrefix("Glaze test"))
        #expect(object.fileName(.json).hasSuffix(".json"))
        #expect(PortableObject.baseName("../../etc/passwd") == "-..-etc-passwd")
        #expect(PortableObject.baseName("   ") == "Lab object")
        #expect(PortableObject.baseName(String(repeating: "a", count: 90)).count == 60)
    }

    @Test func aDropAcceptsALabObjectOrJSONInMemory() async throws {
        let sample = try Fixture.sample
        for type in [UTType.labObject, .json] {
            let incoming = try await IncomingObject(importing: sample, contentType: type)
            guard case .bytes(let bytes) = incoming.content else {
                Issue.record("expected bytes for \(type.identifier)")
                continue
            }
            #expect(bytes == sample)
        }
        let oversized = Data(repeating: 0x20, count: IncomingObject.maximumBytes + 1)
        let refused = try await IncomingObject(importing: oversized, contentType: .labObject)
        guard case .refused(let reason) = refused.content else {
            Issue.record("an oversized drop must arrive refused")
            return
        }
        #expect(reason == .staging(.malformedJSON(file: 1, .tooLarge(limit: IncomingObject.maximumBytes))))
    }

    @Test func aDroppedFileIsSizedBeforeItIsRead() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TransferTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let small = folder.appending(path: "small.anlab")
        let sample = try Fixture.sample
        try sample.write(to: small)
        guard case .bytes(let bytes) = IncomingObject(reading: small).content else {
            Issue.record("expected the file's bytes")
            return
        }
        #expect(bytes == sample)

        let large = folder.appending(path: "large.anlab")
        FileManager.default.createFile(atPath: large.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(IncomingObject.maximumBytes + 1))
        try handle.close()
        guard case .refused(let reason) = IncomingObject(reading: large).content else {
            Issue.record("an oversized file must arrive refused")
            return
        }
        #expect(reason.code == "staging/malformed-json/too-large")

        guard case .refused(let folderReason) = IncomingObject(reading: folder).content else {
            Issue.record("a folder must arrive refused")
            return
        }
        #expect(folderReason == .staging(.unsupportedFileType(file: 1)))
    }

    /// The path a drag takes: the object registered with an item provider on one side, loaded as
    /// an incoming object on the other.
    @Test func anItemProviderCarriesTheCompleteDocument() async throws {
        let provider = NSItemProvider()
        let object = try object
        let sample = try Fixture.sample
        provider.register(object)
        #expect(provider.registeredContentTypes.first == .labObject)
        let incoming: IncomingObject = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: IncomingObject.self) { result in
                continuation.resume(with: result)
            }
        }
        guard case .bytes(let bytes) = incoming.content else {
            Issue.record("expected bytes")
            return
        }
        #expect(bytes == sample)
        #expect(try LabDocument(decoding: bytes).itemID == Fixture.sampleID)
    }
}
