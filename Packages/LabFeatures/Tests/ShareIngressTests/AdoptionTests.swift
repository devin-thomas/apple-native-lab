import Foundation
import LabDomain
import LabStaging
import Testing
@testable import ShareIngress

/// LAB-007: a staged import is adopted only through `ImportAdopter` and the one
/// `OperationService`, as the adapter its folder names, with a grant the person's Add issues, and
/// with a receipt. Shared text that reads like instructions stays data.
@Suite struct AdoptionTests {
    /// The host's composition: one ledger and one service, as `LabDataService` builds them.
    struct Host {
        let ledger = GrantLedger()
        let store = InMemoryOperationStore()
        let service: OperationService

        init() {
            service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
        }

        func makeCollection(_ title: String) async throws -> CollectionID {
            let id = CollectionID()
            _ = try await service.perform(OperationRequest(
                id: RequestID(), operation: .createCollection(draft: CollectionDraft(id: id, title: try EntityTitle(title))), actor: .testAppUI
            ))
            return id
        }

        /// What the host's Add button does: a grant for exactly this import's operation, for the
        /// entry's adapter, revoked when the commit returns.
        func add(_ entry: InboxEntry, from inbox: ShareInbox, into collection: CollectionID) async throws(ImportRejection) -> ImportAdoption {
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
    }

    @Test func sharedContentIsAdoptedAsTheShareExtensionWithAReceipt() async throws {
        let lab = try Station()
        let host = Host()
        let collection = try await host.makeCollection("Reading list")
        let item = NSExtensionItem()
        item.attributedContentText = NSAttributedString(string: "Tide tables")
        item.attachments = [Providers.link("https://example.org/tides")]
        _ = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [item]), via: .shareExtension)
        let inbox = lab.inbox
        let entry = try #require(await inbox.snapshot().entries.first)

        let adoption = try await host.add(entry, from: inbox, into: collection)
        #expect(adoption.receipt.status == .committed)
        #expect(adoption.receipt.admitted.adapter == .shareExtension)
        guard case .createItem(let draft) = adoption.receipt.admitted.operation else { Issue.record("not a create"); return }
        let stored = try await host.service.findItem(draft.id, as: .testAppUI)
        #expect(stored.title.value == "Tide tables")
        #expect(stored.note.value == "https://example.org/tides")
        #expect(stored.collectionID == collection && stored.namespace == .user)
        #expect(await inbox.snapshot().entries.isEmpty)
        #expect(host.ledger.liveGrants.isEmpty, "the grant was revoked after the commit")
    }

    @Test func pastedContentIsAdoptedAsTheAppUI() async throws {
        let lab = try Station()
        let host = Host()
        let collection = try await host.makeCollection("Notes")
        _ = await lab.hostStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Pasted line")]), via: .paste)
        let inbox = lab.inbox
        let entry = try #require(await inbox.snapshot().entries.first)
        let adoption = try await host.add(entry, from: inbox, into: collection)
        #expect(adoption.receipt.admitted.adapter == .appUI)
    }

    @Test func withoutTheAddGrantNothingIsAdopted() async throws {
        let lab = try Station()
        let host = Host()
        let collection = try await host.makeCollection("Notes")
        _ = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Needs approval")]), via: .shareExtension)
        let inbox = lab.inbox
        let entry = try #require(await inbox.snapshot().entries.first)
        let adopter = ImportAdopter(service: host.service, inbox: lab.shared.staging, ledger: host.ledger, adapter: .shareExtension)
        await #expect(throws: ImportRejection.grantMissing) { try await adopter.adopt(entry.id.staging, into: collection) }
        #expect(await host.store.items(in: collection).isEmpty)
        #expect(await inbox.snapshot().entries.count == 1, "the import keeps waiting")
    }

    @Test func instructionLikeSharedTextStaysData() async throws {
        let lab = try Station()
        let host = Host()
        let collection = try await host.makeCollection("Inbox")
        let demoLike = try await host.makeCollection("Other collection")
        let injection = try String(decoding: HostileFixtures.data("prompt-injection.txt"), as: UTF8.self)
        let report = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text(injection)]), via: .shareExtension)
        #expect(report.stagedCount == 1)
        let inbox = lab.inbox
        let entry = try #require(await inbox.snapshot().entries.first)
        #expect(entry.content == .text(injection))
        #expect(entry.origin?.surface == .shareExtension)

        let collectionsBefore = await host.store.collections()
        let adoption = try await host.add(entry, from: inbox, into: collection)

        // Exactly one new item, in the collection the person chose, holding the text as its note.
        #expect(adoption.receipt.admitted.operation.kind == .createItem)
        #expect(adoption.receipt.admitted.adapter == .shareExtension)
        let items = await host.store.items(in: nil)
        #expect(items.count == 1)
        #expect(items.first?.collectionID == collection)
        #expect(items.first?.note.value == injection)
        // Nothing else changed, no collection was archived, and no grant outlived the commit.
        #expect(await host.store.collections().sorted { $0.id.description < $1.id.description }
            == collectionsBefore.sorted { $0.id.description < $1.id.description })
        #expect(await host.store.collection(demoLike)?.isArchived == false)
        #expect(host.ledger.liveGrants.isEmpty)
    }

    @Test func addingTheSameSharedContentTwiceStoresItOnce() async throws {
        let lab = try Station()
        let host = Host()
        let collection = try await host.makeCollection("Notes")
        let inbox = lab.inbox
        _ = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Twice shared")]), via: .shareExtension)
        let first = try await host.add(try #require(await inbox.snapshot().entries.first), from: inbox, into: collection)
        _ = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Twice shared")]), via: .shareExtension)
        let second = try await host.add(try #require(await inbox.snapshot().entries.first), from: inbox, into: collection)
        #expect(!first.isDuplicate && second.isDuplicate)
        #expect(second.receipt == first.receipt)
        #expect(await host.store.items(in: collection).count == 1)
    }

    @Test func filesWaitButCannotBeAdoptedYet() async throws {
        let lab = try Station()
        let host = Host()
        let collection = try await host.makeCollection("Notes")
        _ = await lab.shareStation.receive(
            ItemProviderAttachment.attachments(from: [try Providers.file(SyntheticMedia.bytes(256), type: .png, suggestedName: "Swatch", folder: lab.folder)]),
            via: .shareExtension
        )
        let inbox = lab.inbox
        let entry = try #require(await inbox.snapshot().entries.first)
        #expect(entry.adoptability == .unavailable(.attachmentsNotAdoptable))
        await #expect(throws: ImportRejection.attachmentsNotAdoptable) { try await host.add(entry, from: inbox, into: collection) }
        #expect(await inbox.snapshot().entries.count == 1)
    }
}
