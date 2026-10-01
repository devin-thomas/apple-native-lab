import Foundation
import Testing
@testable import DocumentsEverywhere

@Suite("Provider session")
struct ProviderSessionTests {
    @Test("Provider starts disabled")
    func providerStartsDisabled() {
        let session = ProviderSession()
        #expect(session.state == .disabled)
        #expect(session.mirror.isEmpty)
    }

    @Test("Disconnect never deletes the authoritative source")
    func disconnectNeverDeletesTheAuthoritativeSource() throws {
        let catalog = SampleCatalog.bundled
        let items = try catalog.providerItems()
        var session = ProviderSession()
        try session.connect(mirroring: items)
        #expect(session.state == .connected)
        #expect(session.mirror.count == items.count)
        #expect(session.authoritativeIDs.count == items.count)

        let result = session.disconnect()
        #expect(session.state == .disconnected)
        #expect(session.mirror.isEmpty)
        #expect(result.removedMirrorCount == items.count)
        #expect(result.authoritativeCount == items.count)
        #expect(session.authoritativeIDs.count == items.count)

        // Authoritative fixtures are still readable from the catalog.
        for id in session.authoritativeIDs {
            let data = try catalog.data(for: id)
            #expect(!data.isEmpty)
        }
    }

    @Test("Eviction removes a mirror only")
    func evictionRemovesAMirrorOnly() throws {
        let catalog = SampleCatalog.bundled
        let items = try catalog.providerItems()
        let first = try #require(items.first)
        var session = ProviderSession()
        try session.connect(mirroring: items)

        let result = try session.evict(first.id)
        #expect(result.removedMirrorCount == 1)
        #expect(result.authoritativeCount == items.count)
        #expect(session.mirror[first.id] == nil)
        #expect(session.authoritativeIDs.contains(first.id))
        let bytes = try catalog.data(for: first.id)
        #expect(!bytes.isEmpty)
    }

    @Test("External edit on a mirror preserves revision rules")
    func externalEditOnAMirrorPreservesRevisionRules() throws {
        let items = try SampleCatalog.bundled.providerItems()
        let first = try #require(items.first)
        var session = ProviderSession()
        try session.connect(mirroring: items)

        let accepted = try session.applyExternalEdit(to: first.id, base: first.revision, change: .content)
        #expect(accepted == .accepted(first.revision.afterContentEdit()))
        #expect(session.mirror[first.id]?.revision.content == first.revision.content + 1)

        let conflict = try session.applyExternalEdit(to: first.id, base: first.revision, change: .content)
        guard case .conflict(let expected, let found) = conflict else {
            Issue.record("expected a conflict")
            return
        }
        #expect(expected == first.revision)
        #expect(found.content == first.revision.content + 1)
    }

    @Test("Actions while disabled or disconnected are refused")
    func actionsWhileDisabledOrDisconnectedAreRefused() throws {
        var session = ProviderSession()
        #expect(throws: DocumentsEverywhereError.providerDisabled) {
            try session.evict(ProviderItemID(rawValue: "sample.harbor-note"))
        }
        let items = try SampleCatalog.bundled.providerItems()
        try session.connect(mirroring: items)
        _ = session.disconnect()
        #expect(throws: DocumentsEverywhereError.providerDisconnected) {
            try session.evict(items[0].id)
        }
    }
}
