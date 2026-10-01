import Foundation
import LabDomain
import PortableObjects
import Testing
@testable import DocumentsEverywhere

/// LAB-009-B fixture qualification. A connected ProviderSession is a model, never a registered
/// File Provider domain. Check authority by comparing the catalog bytes, not its result flag.
@Suite("Documents Everywhere qualification")
struct QualificationTests {
    @Test func editsEvictionDisconnectAndReconnectPreserveAuthority() throws {
        let catalog = SampleCatalog.bundled
        let items = try catalog.providerItems()
        let before = try items.map { try catalog.data(for: $0.id) }
        var session = ProviderSession()
        try session.connect(mirroring: items)
        let connected = session
        #expect(throws: DocumentsEverywhereError.invalidInput("The sample provider is already connected.")) {
            try session.connect(mirroring: items)
        }
        #expect(session == connected)
        for item in items {
            let metadata = item.revision.afterMetadataEdit()
            #expect(try session.applyExternalEdit(to: item.id, base: item.revision, change: .metadata) == .accepted(metadata))
            let edited = session
            #expect(try session.applyExternalEdit(to: item.id, base: item.revision, change: .content)
                == .conflict(expected: item.revision, found: metadata))
            #expect(session == edited)
            #expect(try session.applyExternalEdit(to: item.id, base: metadata, change: .content)
                == .accepted(metadata.afterContentEdit()))
            #expect(try session.evict(item.id).removedMirrorCount == 1)
            #expect(try session.evict(item.id).removedMirrorCount == 0)
        }
        _ = session.disconnect()
        #expect(session.disconnect().removedMirrorCount == 0)
        for item in items {
            #expect(throws: DocumentsEverywhereError.providerDisconnected) {
                try session.applyExternalEdit(to: item.id, base: item.revision, change: .content)
            }
        }
        #expect(try items.map { try catalog.data(for: $0.id) } == before)
        try session.connect(mirroring: catalog.providerItems())
        #expect(session.mirror.values.allSatisfy { $0.revision == .initial })
    }

    @Test func anActorWithoutCommitPermissionCannotAdopt() async throws {
        let lab = try await TestLab.make()
        defer { try? FileManager.default.removeItem(at: lab.stagingRoot) }
        let backend = ServiceBackend(service: lab.service, actor: ActorScope(adapter: .appUI, grants: [.read, .propose]))
        let importer = try PortableObjectsImporter(backend: backend, stagingRoot: lab.stagingRoot.appending(path: "denied"))
        let adopter = SampleAdopter(importer: importer)
        await #expect(throws: DocumentsEverywhereError.notAuthorized) {
            try await adopter.adopt(ProviderItemID(rawValue: "sample.harbor-note"), into: lab.inbox)
        }
        #expect(await lab.snapshot().isEmpty)
    }

    @Test func cancellationBeforeAdoptionCommitsNothingAndRetryCreatesOnce() async throws {
        let lab = try await TestLab.make()
        defer { try? FileManager.default.removeItem(at: lab.stagingRoot) }
        let id = ProviderItemID(rawValue: "sample.harbor-note")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await lab.adopter.adopt(id, into: lab.inbox)
        }
        await #expect(throws: DocumentsEverywhereError.cancelled) { try await cancelled.value }
        #expect(await lab.snapshot().isEmpty)
        #expect(await lab.importer.waitingImports().isEmpty)
        let result = try await lab.adopter.adopt(id, into: lab.inbox)
        #expect(result.change == .created)
        let before = await lab.snapshot()
        await #expect(throws: DocumentsEverywhereError.invalidInput("This sample is already in the lab with the same content.")) {
            try await lab.adopter.adopt(id, into: lab.inbox)
        }
        #expect(await lab.snapshot() == before)
        // Current behavior: the refused duplicate retains its staged review. The browser has no
        // Close Review action; record this finding rather than claiming all refusals clean up.
        #expect(await lab.importer.waitingImports().count == 1)
    }

    @Test func previewEscapesDocumentMarkupWithoutActivatingAProvider() throws {
        var root = try LabDocument(decoding: SampleCatalog.bundled.data(for: ProviderItemID(rawValue: "sample.harbor-note"))).root
        root["title"] = .string("<script>sample</script> & \"quoted\"")
        let bytes = try LabDocument(validating: .object(root)).encoded()
        let preview = try DocumentPreviewBuilder.preview(of: bytes)
        #expect(preview.html.contains("&lt;script&gt;sample&lt;/script&gt; &amp; &quot;quoted&quot;"))
        #expect(!preview.html.contains("<script>"))
        #expect(!preview.html.contains("<iframe"))
        #expect(ProviderSession().state == .disabled)
    }
}
