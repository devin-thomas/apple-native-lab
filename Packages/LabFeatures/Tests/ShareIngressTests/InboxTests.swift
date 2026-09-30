import Foundation
import LabDomain
import LabStaging
import Testing
import UniformTypeIdentifiers
@testable import ShareIngress

/// LAB-007: the inbox lists what waits, validated again from its bytes, sets damaged imports
/// aside without blocking others, and treats origins as display data only.
@Suite struct InboxTests {
    @Test func aDamagedImportIsSetAsideAndTheRestStillList() async throws {
        let lab = try Station()
        let report = await lab.shareStation.receive(
            ItemProviderAttachment.attachments(from: [Providers.text("Will be damaged"), Providers.text("Stays fine")]),
            via: .shareExtension
        )
        let damaged = report.waitingIDs[0]
        let record = lab.shared.staging.root.appending(path: "pending/\(damaged)/record.json")
        var bytes = try Data(contentsOf: record)
        bytes[bytes.count - 3] ^= 0x01
        try bytes.write(to: record)

        let snapshot = await lab.inbox.snapshot()
        #expect(snapshot.entries.map(\.content) == [.text("Stays fine")])
        #expect(snapshot.quarantined.count == 1)
        let setAside = try #require(snapshot.quarantined.first)
        #expect(setAside.source == .shareExtension)
        #expect(setAside.origin?.stagingID == damaged)
        #expect(setAside.origin?.position == 1)
        #expect(setAside.code != nil)

        // Removing it clears its origin too, and a new share of the same text stages again.
        try await lab.inbox.removeQuarantined(setAside)
        #expect(lab.shared.origins.origin(for: damaged) == nil)
        let again = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Will be damaged")]), via: .shareExtension)
        #expect(again.outcomes.map(\.result) == [.staged(damaged)])
        #expect(await lab.inbox.snapshot().quarantined.isEmpty)
    }

    @Test func aForgedOrMismatchedOriginReadsAsUnknown() async throws {
        let lab = try Station()
        let report = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Origin probe")]), via: .shareExtension)
        let id = report.waitingIDs[0]
        let file = lab.shared.origins.root.appending(path: "\(id).json")
        let valid = try Data(contentsOf: file)
        #expect(ImportOrigin(decoding: valid, expecting: id) != nil)

        // A smuggled field, another ID, a bad surface, a position past the count, duplicate keys.
        var object = try #require(try JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["grant"] = "commit-destructive"
        let smuggled = try JSONSerialization.data(withJSONObject: object)
        #expect(ImportOrigin(decoding: smuggled, expecting: id) == nil)
        #expect(ImportOrigin(decoding: valid, expecting: StagingID(rawValue: UUID())) == nil)
        let text = String(decoding: valid, as: UTF8.self)
        #expect(ImportOrigin(decoding: Data(text.replacingOccurrences(of: "share-extension", with: "model-tool").utf8), expecting: id) == nil)
        #expect(ImportOrigin(decoding: Data(text.replacingOccurrences(of: #""position":1"#, with: #""position":2"#).utf8), expecting: id) == nil)
        #expect(ImportOrigin(decoding: Data(text.replacingOccurrences(of: #"{"#, with: #"{"count":1,"#).utf8), expecting: id) == nil)
        #expect(ImportOrigin(decoding: Data(repeating: 0x20, count: 2_000), expecting: id) == nil)

        // In the folder, a smuggled origin reads as unknown and the import still lists.
        try FileManager.default.removeItem(at: file)
        try smuggled.write(to: file)
        let entry = try #require(await lab.inbox.snapshot().entries.first)
        #expect(entry.origin == nil)
        #expect(entry.adoptability == .ready)

        // An origin that claims a surface this folder never takes is ignored too.
        let pasted = try #require(ImportOrigin(
            stagingID: id, surface: .paste, receivedAt: Date(), batch: BatchID(), position: 1, count: 1, contentType: nil
        ))
        try FileManager.default.removeItem(at: file)
        #expect(lab.shared.origins.record(pasted))
        #expect(await lab.inbox.snapshot().entries.first?.origin == nil)
    }

    @Test func aLinkedOriginFileIsNotFollowed() async throws {
        let lab = try Station()
        let report = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Link probe")]), via: .shareExtension)
        let id = report.waitingIDs[0]
        let file = lab.shared.origins.root.appending(path: "\(id).json")
        let elsewhere = lab.folder.appending(path: "elsewhere.json")
        try FileManager.default.moveItem(at: file, to: elsewhere)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: elsewhere)
        #expect(lab.shared.origins.origin(for: id) == nil)
    }

    @Test func discardingRemovesTheImportAndItsOrigin() async throws {
        let lab = try Station()
        let report = await lab.hostStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Not wanted")]), via: .paste)
        let entry = try #require(await lab.inbox.snapshot().entries.first)
        try await lab.inbox.discard(entry.id)
        #expect(await lab.inbox.snapshot().entries.isEmpty)
        #expect(lab.host.origins.origin(for: report.waitingIDs[0]) == nil)
        await #expect(throws: ImportRejection.self) {
            try await ShareInbox(areas: [lab.host]).discard(InboxEntry.ID(source: .shareExtension, staging: report.waitingIDs[0]))
        }
    }

    @Test func orphanedOriginsAreSweptOnlyOnceStale() async throws {
        let lab = try Station()
        let orphan = try #require(ImportOrigin(
            stagingID: StagingID(rawValue: UUID()), surface: .paste, receivedAt: Date(), batch: BatchID(), position: 1, count: 1, contentType: nil
        ))
        #expect(lab.host.origins.record(orphan))
        try Data("junk".utf8).write(to: lab.host.origins.root.appending(path: "notes.txt"))

        _ = await ShareInbox(areas: [lab.host]).snapshot()
        #expect(lab.host.origins.origin(for: orphan.stagingID) != nil, "a fresh origin may belong to an intake still running")
        #expect(!FileManager.default.fileExists(atPath: lab.host.origins.root.appending(path: "notes.txt").path(percentEncoded: false)))

        let later = ShareInbox(areas: [lab.host], now: { Date().addingTimeInterval(OriginLog.orphanedAfter + 60) })
        _ = await later.snapshot()
        #expect(lab.host.origins.origin(for: orphan.stagingID) == nil)
    }

    @Test func anEntryDescribesItselfWithoutItsContent() async throws {
        let lab = try Station()
        _ = await lab.hostStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("sentinel-91C2 private")]), via: .paste)
        let entry = try #require(await lab.inbox.snapshot().entries.first)
        #expect(!String(describing: entry).contains("sentinel"))
        #expect(!String(reflecting: entry).contains("sentinel"))
        #expect(entry.headline == "sentinel-91C2 private")
    }

    @Test func bothFoldersListTogetherInArrivalOrder() async throws {
        let lab = try Station()
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let first = IngressStation(area: lab.shared, now: { [clock] in clock })
        clock += 5
        let second = IngressStation(area: lab.host, now: { [clock] in clock })
        _ = await second.receive(ItemProviderAttachment.attachments(from: [Providers.text("Pasted later")]), via: .paste)
        _ = await first.receive(ItemProviderAttachment.attachments(from: [Providers.text("Shared first"), Providers.text("Shared second")]), via: .shareExtension)
        let entries = await lab.inbox.snapshot().entries
        #expect(entries.map(\.content) == [.text("Shared first"), .text("Shared second"), .text("Pasted later")])
        #expect(entries.map(\.source) == [.shareExtension, .shareExtension, .host])
    }
}
