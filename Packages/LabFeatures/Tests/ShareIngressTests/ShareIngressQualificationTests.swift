import Darwin
import Foundation
import LabDomain
import LabStaging
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import ShareIngress

/// LAB-007-B: the qualification cases LAB-007-A's tests left open. Fixture path: real
/// `NSItemProvider`s, real files and file coordination, real staging folders in a temporary
/// directory, and an in-memory store behind `OperationService` with `GrantAuthorizationPolicy`.
/// Nothing here downloads from iCloud, runs the share sheet, or touches a device.
///
/// A `withKnownIssue` marks a finding recorded in the ticket's completion record. It fails once
/// the behavior is fixed, so the record is updated with it.
@Suite struct ShareIngressQualificationTests {
    // MARK: Criterion 1: cloud-backed attachments can be cancelled safely

    /// Files from iCloud Drive are read through `NSFileCoordinator`, which waits while the file
    /// provider downloads. A writer holding the file stands in for that download here. Cancelling
    /// returns at once, keeps nothing, and the same file imports once the download finishes.
    @Test(.timeLimit(.minutes(1)))
    func aChosenFileStillDownloadingCanBeCancelled() async throws {
        let lab = try Station()
        let file = lab.folder.appending(path: "Tide log.txt")
        try Data("High water 12:04.".utf8).write(to: file)
        let download = CoordinatedWriter(holding: file)
        await download.waitUntilHolding()

        let station = lab.hostStation
        let intake = Task { await station.receive(ChosenFile.attachments(from: [file]), via: .filePicker) }
        try await Task.sleep(for: .milliseconds(300))
        let started = ContinuousClock.now
        intake.cancel()
        let report = await intake.value
        #expect(ContinuousClock.now - started < .seconds(2), "the cancel did not wait for the download")
        #expect(report.wasCancelled)
        #expect(report.outcomes.map(\.result) == [.cancelled])
        #expect(await lab.host.staging.waitingImports().isEmpty)
        #expect(lab.leftovers(in: lab.host, "incoming").isEmpty)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "ShareIngress-\(report.batch)")
        #expect(!FileManager.default.fileExists(atPath: scratch.path(percentEncoded: false)))

        // The download finishes; a new import of the same file stages normally.
        download.release()
        let again = await station.receive(ChosenFile.attachments(from: [file]), via: .filePicker)
        #expect(again.stagedCount == 1)
        #expect(await lab.inbox.snapshot().entries.map(\.content) == [.files([InboxFile(name: "Tide log.txt", byteCount: 17)])])
    }

    /// A cloud-backed photo whose download fails is refused on its own, as unreadable, not as a
    /// cancellation. The rest of the share stages, and the next share is unaffected.
    @Test func aCloudDownloadThatFailsIsRefusedAloneAndTheNextShareStages() async throws {
        let lab = try Station()
        let failing = NSItemProvider()
        failing.suggestedName = "Harbor"
        failing.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { completion in
            completion(nil, false, URLError(.networkConnectionLost))
            return Progress(totalUnitCount: 1)
        }
        let report = await lab.shareStation.receive(
            ItemProviderAttachment.attachments(from: [Providers.text("Before the photo"), failing, Providers.text("After the photo")]),
            via: .shareExtension
        )
        #expect(!report.wasCancelled)
        #expect(report.outcomes.map(\.result.rejection) == [nil, .unreadableSource(file: 2), nil])
        #expect(report.summary == "2 items are waiting for review, 1 was refused.")
        #expect(lab.leftovers(in: lab.shared, "incoming").isEmpty)
        let next = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Next share")]), via: .shareExtension)
        #expect(next.stagedCount == 1)
    }

    /// A share cancelled before it starts reads nothing at all.
    @Test func aShareCancelledBeforeItStartsReadsNothing() async throws {
        let lab = try Station()
        let sources = [CountingSource(), CountingSource()]
        let station = lab.shareStation
        let report = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await station.receive(sources, via: .shareExtension)
        }.value
        #expect(report.wasCancelled)
        #expect(sources.allSatisfy { $0.loadCount == 0 })
        #expect(await lab.shared.staging.waitingImports().isEmpty)
    }

    /// A cancelled share of the same content leaves nothing that makes the retry a duplicate or
    /// changes its origin: the retry stages under the same content-derived ID, with its own origin.
    @Test func aShareCancelledWhileDownloadingCanBeSharedAgain() async throws {
        let lab = try Station()
        let gate = ProviderGate()
        let station = lab.shareStation
        let intake = Task {
            await station.receive(ItemProviderAttachment.attachments(from: [Providers.text("Tide tables"), Providers.slowFile(gate)]), via: .shareExtension)
        }
        await gate.waitUntilStarted()
        intake.cancel()
        let cancelled = await intake.value
        #expect(cancelled.wasCancelled)

        let photo = lab.folder.appending(path: "photo.jpeg")
        try SyntheticMedia.bytes(512).write(to: photo)
        let retry = await station.receive(ItemProviderAttachment.attachments(from: [
            Providers.text("Tide tables"),
            try Providers.file(SyntheticMedia.bytes(512), type: .jpeg, suggestedName: "Harbor", folder: lab.folder),
        ]), via: .shareExtension)
        #expect(retry.stagedCount == 2 && retry.duplicateCount == 0)
        let entries = await lab.inbox.snapshot().entries
        #expect(entries.compactMap(\.origin?.batch) == [retry.batch, retry.batch])
        #expect(entries.compactMap(\.origin?.position) == [1, 2])
    }

    // MARK: Criterion 2: multiple attachments preserve order and provenance

    @Test func thirtyTwoAttachmentsStageInTheirOrderWithTheirPositions() async throws {
        let lab = try Station()
        let texts = (1...32).map { String(format: "Buoy %02d", $0) }
        let report = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: texts.map(Providers.text)), via: .shareExtension)
        #expect(report.stagedCount == 32)
        let entries = await lab.inbox.snapshot().entries
        #expect(entries.map(\.content) == texts.map { .text($0) })
        #expect(entries.compactMap(\.origin?.position) == Array(1...32))
        #expect(entries.allSatisfy { $0.origin?.count == 32 && $0.origin?.batch == report.batch })
    }

    /// The share sheet can hand over several extension items. Positions run across all of them,
    /// and a link keeps a title only from an item that holds nothing else.
    @Test func attachmentsFromSeveralExtensionItemsAreNumberedAcrossTheShare() async throws {
        let lab = try Station()
        let page = NSExtensionItem()
        page.attributedContentText = NSAttributedString(string: "Tide tables")
        page.attachments = [Providers.link("https://example.org/tide-tables"), Providers.text("Spring tide on Friday.")]
        let single = NSExtensionItem()
        single.attributedTitle = NSAttributedString(string: "Harbor chart")
        single.attachments = [Providers.link("https://example.org/chart")]
        let photo = NSExtensionItem()
        photo.attachments = [try Providers.file(SyntheticMedia.bytes(256), type: .png, suggestedName: "Buoy", folder: lab.folder)]

        let report = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [page, single, photo]), via: .shareExtension)
        #expect(report.outcomes.map(\.position) == [1, 2, 3, 4])
        let entries = await lab.inbox.snapshot().entries
        #expect(entries.map(\.content) == [
            .link(URL(string: "https://example.org/tide-tables")!, title: nil),
            .text("Spring tide on Friday."),
            .link(URL(string: "https://example.org/chart")!, title: "Harbor chart"),
            .files([InboxFile(name: "Buoy.png", byteCount: 256)]),
        ])
        #expect(entries.compactMap(\.origin?.position) == [1, 2, 3, 4])
        #expect(entries.allSatisfy { $0.origin?.count == 4 })
    }

    /// The host reads the extension's folder in another process, often after a relaunch. A new
    /// inbox over the same folders lists the same imports in the same order with the same origins.
    @Test func orderAndProvenanceSurviveARelaunch() async throws {
        let lab = try Station()
        _ = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [
            Providers.link("https://example.org/tide-tables"), Providers.text("Second"), Providers.text("Third"),
        ]), via: .shareExtension)
        let before = await lab.inbox.snapshot()

        let reopened = ShareInbox(areas: [
            try IngressArea(source: .host, root: lab.folder.appending(path: "host")),
            try IngressArea(source: .shareExtension, root: lab.folder.appending(path: "group")),
        ])
        let after = await reopened.snapshot()
        #expect(after.entries.map(\.id) == before.entries.map(\.id))
        #expect(after.entries.map(\.origin) == before.entries.map(\.origin))
        #expect(after.entries.map(\.content) == before.entries.map(\.content))
    }

    /// Adding one import of a share leaves the others waiting in order, each still "n of 4".
    @Test func addingOneImportLeavesTheRestInOrderWithTheirPositions() async throws {
        let lab = try ShowcaseLab()
        let collection = try await lab.makeCollection("Field notes")
        _ = await lab.folders.shareStation.receive(ItemProviderAttachment.attachments(from: [
            Providers.text("One"), Providers.text("Two"), Providers.text("Three"), Providers.text("Four"),
        ]), via: .shareExtension)
        let second = try #require(await lab.folders.inbox.snapshot().entries.dropFirst().first)
        _ = try await lab.add(second, into: collection)

        let left = await lab.folders.inbox.snapshot().entries
        #expect(left.map(\.content) == [.text("One"), .text("Three"), .text("Four")])
        #expect(left.compactMap(\.origin?.position) == [1, 3, 4])
        #expect(left.allSatisfy { $0.origin?.count == 4 })
    }

    /// Finding: the inbox orders intakes by the second they began, then by their random batch ID.
    /// Two intakes that begin within the same second can therefore list the later one first. The
    /// order within one intake is always kept.
    @Test func twoIntakesInTheSameSecondListInArrivalOrder() async throws {
        let second = Date(timeIntervalSince1970: 1_800_000_000)
        var inverted: (Station, String, String)?
        for attempt in 0..<64 where inverted == nil {
            let lab = try Station()
            let station = IngressStation(area: lab.host, now: { second })
            let first = await station.receive(ItemProviderAttachment.attachments(from: [Providers.text("Pasted first \(attempt)")]), via: .paste)
            let later = await station.receive(ItemProviderAttachment.attachments(from: [Providers.text("Pasted second \(attempt)")]), via: .paste)
            if later.batch.description < first.batch.description {
                inverted = (lab, "Pasted first \(attempt)", "Pasted second \(attempt)")
            }
        }
        let (lab, first, later) = try #require(inverted, "two intakes whose batch IDs sort against their arrival")
        let listed = await lab.inbox.snapshot().entries.map(\.content)
        withKnownIssue("Intakes in the same second are ordered by their random batch ID, not by arrival.") {
            #expect(listed == [.text(first), .text(later)])
        }
    }

    // MARK: Criterion 3: malformed and oversized payloads never block future imports

    /// Every hostile fixture meets its refusal on the path it can arrive through, and afterwards
    /// a good import still stages and is added with a receipt.
    @Test func everyHostileFixtureIsHandledAndTheNextImportIsStillAdded() async throws {
        let lab = try ShowcaseLab()
        let collection = try await lab.makeCollection("Field notes")
        let folders = lab.folders

        // Through the share sheet: ill-formed text, and a photo under each hostile name.
        let malformed = try HostileFixtures.data("malformed-utf8.txt")
        let bad = await folders.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.utf8Bytes(malformed)]), via: .shareExtension)
        #expect(bad.outcomes.map(\.result.rejection) == [.malformedUTF8(offset: try #require(malformed.firstIndex(of: 0xC0)))])

        let names = try TraversalNames.load().filter { $0.name != nil }
        let hostileNames = try names.map { try Providers.file(SyntheticMedia.bytes(32), type: .png, suggestedName: $0.name, folder: folders.folder) }
        var refusedNames = 0
        for chunk in stride(from: 0, to: hostileNames.count, by: 30) {
            let slice = Array(hostileNames[chunk..<min(chunk + 30, hostileNames.count)])
            let report = await folders.shareStation.receive(ItemProviderAttachment.attachments(from: slice), via: .shareExtension)
            for (outcome, name) in zip(report.outcomes, names[chunk...]) {
                guard case .refused(.unsafePath(_, let reason)) = outcome.result else {
                    Issue.record("\(name.id) was not refused as an unsafe path: \(outcome.result)")
                    continue
                }
                #expect(reason.rawValue == name.expect, "\(name.id)")
                refusedNames += 1
            }
        }
        #expect(refusedNames == names.count)

        // Through the file picker (and a pasted Finder copy, which reads the same way): JSON too
        // deep to parse and JSON naming a field twice.
        let deep = folders.folder.appending(path: "deeply-nested.json")
        let twice = folders.folder.appending(path: "duplicate-keys.json")
        try HostileFixtures.data("deeply-nested.json").write(to: deep)
        try HostileFixtures.data("duplicate-keys.json").write(to: twice)
        let chosen = await folders.hostStation.receive(ChosenFile.attachments(from: [deep, twice]), via: .filePicker)
        #expect(chosen.outcomes.map(\.result.rejection) == [
            .malformedJSON(file: 1, .tooDeep(limit: 16)), chosen.outcomes[1].result.rejection,
        ])
        if case .refused(.malformedJSON(_, .duplicateKey)) = chosen.outcomes[1].result {} else {
            Issue.record("duplicate-keys.json was not refused for its duplicate key: \(chosen.outcomes[1].result)")
        }
        let pastedCopy = await folders.hostStation.receive(
            ItemProviderAttachment.attachments(from: [NSItemProvider(object: deep as NSURL)], acceptsFileReferences: true), via: .paste
        )
        #expect(pastedCopy.outcomes.map(\.result.rejection) == [.malformedJSON(file: 1, .tooDeep(limit: 16))])

        // A note longer than an item can hold stages, and waits without blocking anything.
        let long = String(decoding: try HostileFixtures.data("oversized-note.txt"), as: UTF8.self)
        #expect(await folders.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text(long)]), via: .shareExtension).stagedCount == 1)

        // A forged staging record planted in the extension's folder is set aside when listed.
        let planted = folders.shared.staging.root.appending(path: "pending/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: planted, withIntermediateDirectories: true)
        try HostileFixtures.data("forged-staging-record.json").write(to: planted.appending(path: "record.json"))

        // Nothing above blocks the next share, and it is added with a receipt.
        #expect(await folders.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Harbor walk")]), via: .shareExtension).stagedCount == 1)
        let snapshot = await folders.inbox.snapshot()
        #expect(snapshot.quarantined.count == 1)
        #expect(snapshot.quarantined.first?.code == ImportRejection.unknownRecordField.code)
        // Both shares began in the same second, so their order is left to the ordering finding.
        #expect(Set(snapshot.entries.map(\.content)) == [.text(long), .text("Harbor walk")])
        let waiting = try #require(snapshot.entries.first { $0.content == .text(long) })
        #expect(waiting.adoptability == .unavailable(.textTooLongForNote(limit: ItemNote.maximumLength)))
        let good = try #require(snapshot.entries.first { $0.content == .text("Harbor walk") })
        let adoption = try await lab.add(good, into: collection)
        #expect(adoption.receipt.status == .committed)
        #expect(await lab.store.items(in: collection).map(\.title.value) == ["Harbor walk"])
        #expect(folders.leftovers(in: folders.shared, "incoming").isEmpty)
        #expect(folders.leftovers(in: folders.host, "incoming").isEmpty)
    }

    /// Text one byte over the standard 2 MiB limit is refused before anything is kept, on both of
    /// the provider's text paths, and the next share stages.
    @Test func textOverTheStandardLimitIsRefusedBeforeItIsKept() async throws {
        let lab = try Station()
        let limit = ImportLimits.standard.maximumTextBytes
        let oversized = String(repeating: "a", count: limit + 1)
        let report = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [
            Providers.utf8Bytes(Data(oversized.utf8)), Providers.text(oversized),
        ]), via: .shareExtension)
        #expect(report.outcomes.map(\.result.rejection) == [.textTooLarge(limit: limit), .textTooLarge(limit: limit)])
        #expect(lab.leftovers(in: lab.shared, "incoming").isEmpty)
        #expect(await lab.shared.staging.waitingImports().isEmpty)
        #expect(await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Next share")]), via: .shareExtension).stagedCount == 1)
    }

    /// A file one byte past the standard 1 GiB share budget is refused from its size alone, before
    /// a byte is copied, through the share sheet and the file picker. The file is sparse, so the
    /// test writes almost nothing.
    @Test(.timeLimit(.minutes(1)))
    func aFileOverTheWholeShareBudgetIsRefusedWithoutBeingCopied() async throws {
        let lab = try Station()
        let limit = ImportLimits.standard.maximumTotalBytes
        let huge = lab.folder.appending(path: "Harbor survey.mov")
        #expect(FileManager.default.createFile(atPath: huge.path(percentEncoded: false), contents: nil))
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(limit) + 1)
        try handle.close()

        let provider = NSItemProvider()
        provider.suggestedName = "Harbor survey"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.quickTimeMovie.identifier, fileOptions: [], visibility: .all) { completion in
            completion(huge, false, nil)
            return nil
        }
        let started = ContinuousClock.now
        let shared = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [provider, Providers.text("Caption")]), via: .shareExtension)
        let chosen = await lab.hostStation.receive(ChosenFile.attachments(from: [huge]), via: .filePicker)
        #expect(ContinuousClock.now - started < .seconds(10), "nothing was copied")
        #expect(shared.outcomes.map(\.result.rejection) == [.totalSizeTooLarge(limit: limit), nil])
        #expect(chosen.outcomes.map(\.result.rejection) == [.totalSizeTooLarge(limit: limit)])
        #expect(lab.leftovers(in: lab.shared, "incoming").isEmpty && lab.leftovers(in: lab.host, "incoming").isEmpty)
        for report in [shared, chosen] {
            let scratch = FileManager.default.temporaryDirectory.appending(path: "ShareIngress-\(report.batch)")
            #expect(!FileManager.default.fileExists(atPath: scratch.path(percentEncoded: false)))
        }
        // The budget is per share: the next one starts with the whole budget again.
        let next = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [
            try Providers.file(SyntheticMedia.bytes(4_096), type: .quickTimeMovie, suggestedName: "Clip", folder: lab.folder),
        ]), via: .shareExtension)
        #expect(next.stagedCount == 1)
    }

    /// An import damaged on disk is set aside, and the rest of the same share is still added.
    @Test func aSetAsideImportDoesNotBlockAddingTheRest() async throws {
        let lab = try ShowcaseLab()
        let collection = try await lab.makeCollection("Field notes")
        let report = await lab.folders.shareStation.receive(
            ItemProviderAttachment.attachments(from: [Providers.text("Damaged"), Providers.text("Intact")]), via: .shareExtension
        )
        let record = lab.folders.shared.staging.root.appending(path: "pending/\(report.waitingIDs[0])/record.json")
        var bytes = try Data(contentsOf: record)
        bytes[bytes.count - 3] ^= 0x01
        try bytes.write(to: record)

        let snapshot = await lab.folders.inbox.snapshot()
        #expect(snapshot.quarantined.count == 1)
        let intact = try #require(snapshot.entries.first)
        #expect(intact.content == .text("Intact") && intact.origin?.position == 2)
        #expect(try await lab.add(intact, into: collection).receipt.status == .committed)
    }

    // MARK: Step 3: denial

    @Test func anApprovalForAnotherCollectionAddsNothing() async throws {
        let lab = try ShowcaseLab()
        let approved = try await lab.makeCollection("Approved")
        let other = try await lab.makeCollection("Other")
        let entry = try await lab.waitingNote("Goes where approved")
        let record = try await lab.folders.shared.staging.validatedRecord(entry.id.staging)
        let grant = try lab.ledger.issue(for: try ImportAdopter.operation(for: record, into: approved), to: .shareExtension)
        defer { lab.ledger.revoke(grant.id) }
        let adopter = ImportAdopter(service: lab.service, inbox: lab.folders.shared.staging, ledger: lab.ledger, adapter: .shareExtension)
        await #expect(throws: ImportRejection.grantOutOfScope) { try await adopter.adopt(entry.id.staging, into: other) }
        #expect(await lab.store.items(in: nil).isEmpty)
        #expect(await lab.folders.inbox.snapshot().entries.map(\.id) == [entry.id], "the import keeps waiting")
    }

    /// An approval given to the app UI does not let the share extension's import in: the grant
    /// names its adapter.
    @Test func anApprovalForTheAppUICannotAddWhatTheShareExtensionStaged() async throws {
        let lab = try ShowcaseLab()
        let collection = try await lab.makeCollection("Field notes")
        let entry = try await lab.waitingNote("Shared from another app")
        let record = try await lab.folders.shared.staging.validatedRecord(entry.id.staging)
        let grant = try lab.ledger.issue(for: try ImportAdopter.operation(for: record, into: collection), to: .appUI)
        defer { lab.ledger.revoke(grant.id) }
        let adopter = ImportAdopter(service: lab.service, inbox: lab.folders.shared.staging, ledger: lab.ledger, adapter: entry.source.adapter)
        #expect(entry.source.adapter == .shareExtension)
        await #expect(throws: ImportRejection.grantOutOfScope) { try await adopter.adopt(entry.id.staging, into: collection) }
        #expect(await lab.store.items(in: nil).isEmpty)
    }

    @Test func anExpiredApprovalAddsNothing() async throws {
        let clock = SteppedGrantClock()
        let lab = try ShowcaseLab(ledger: GrantLedger(clock: clock))
        let collection = try await lab.makeCollection("Field notes")
        let entry = try await lab.waitingNote("Approved, then left too long")
        let record = try await lab.folders.shared.staging.validatedRecord(entry.id.staging)
        _ = try lab.ledger.issue(for: try ImportAdopter.operation(for: record, into: collection), to: .shareExtension, lifetime: .seconds(30))
        clock.advance(by: .seconds(31))
        let adopter = ImportAdopter(service: lab.service, inbox: lab.folders.shared.staging, ledger: lab.ledger, adapter: .shareExtension)
        await #expect(throws: ImportRejection.grantExpired) { try await adopter.adopt(entry.id.staging, into: collection) }
        #expect(await lab.store.items(in: nil).isEmpty)
        #expect(await lab.folders.inbox.snapshot().entries.count == 1)
    }

    /// A model tool can never add an import: no grant can be issued to it, and the adopter refuses.
    @Test func aModelToolCannotAddAnImport() async throws {
        let lab = try ShowcaseLab()
        let collection = try await lab.makeCollection("Field notes")
        let entry = try await lab.waitingNote("A model read this")
        let record = try await lab.folders.shared.staging.validatedRecord(entry.id.staging)
        let operation = try ImportAdopter.operation(for: record, into: collection)
        #expect(throws: GrantError.exceedsAdapterCeiling(.createItem)) { try lab.ledger.issue(for: operation, to: .modelTool) }
        let adopter = ImportAdopter(service: lab.service, inbox: lab.folders.shared.staging, ledger: lab.ledger, adapter: .modelTool)
        await #expect(throws: ImportRejection.self) { try await adopter.adopt(entry.id.staging, into: collection) }
        #expect(await lab.store.items(in: nil).isEmpty)
    }

    /// A demo collection, or one of the person's collections archived after the review, cannot
    /// take the import. It keeps waiting, and the Add succeeds once a usable collection is chosen.
    @Test func aDemoOrArchivedCollectionCannotTakeAnImport() async throws {
        let lab = try ShowcaseLab()
        let seed = try ShareIngressShowcaseFile.load().seed
        _ = try await lab.confirm(.resetDemo(seed: seed), request: RequestID())
        let demo = try #require(seed.collections.first?.id)
        let archived = try await lab.makeCollection("Archived after review")
        let entry = try await lab.waitingNote("Needs a home")
        _ = try await lab.confirm(.archiveCollection(id: archived, expected: .initial), request: RequestID())

        await #expect(throws: ImportRejection.destinationUnavailable) { _ = try await lab.add(entry, into: demo) }
        await #expect(throws: ImportRejection.destinationUnavailable) { _ = try await lab.add(entry, into: archived) }
        #expect(await lab.store.items(in: nil).count == seed.items.count)
        let usable = try await lab.makeCollection("Field notes")
        #expect(try await lab.add(entry, into: usable).receipt.status == .committed)
    }

    // MARK: Step 3: cancellation

    @Test func aCancelledAddCommitsNothingAndTheImportKeepsWaiting() async throws {
        let lab = try ShowcaseLab()
        let collection = try await lab.makeCollection("Field notes")
        let entry = try await lab.waitingNote("Add me later")
        let result = await Task { () async -> Result<ImportAdoption, ImportRejection> in
            withUnsafeCurrentTask { $0?.cancel() }
            do throws(ImportRejection) { return .success(try await lab.add(entry, into: collection)) } catch { return .failure(error) }
        }.value
        #expect(result == .failure(.cancelled))
        #expect(await lab.store.items(in: nil).isEmpty)
        #expect(lab.ledger.liveGrants.isEmpty)
        #expect(await lab.folders.inbox.snapshot().entries.map(\.id) == [entry.id])
        #expect(try await lab.add(entry, into: collection).receipt.status == .committed)
    }

    // MARK: Step 3: stale state

    /// Another window removed the import after this one listed it: the Add finds nothing to add.
    @Test func anImportRemovedElsewhereCannotBeAdded() async throws {
        let lab = try ShowcaseLab()
        let collection = try await lab.makeCollection("Field notes")
        let entry = try await lab.waitingNote("Removed in the other window")
        try await ShareInbox(areas: [lab.folders.host, lab.folders.shared]).discard(entry.id)
        await #expect(throws: ImportRejection.notFound) { _ = try await lab.add(entry, into: collection) }
        #expect(await lab.store.items(in: nil).isEmpty)
        #expect(lab.ledger.liveGrants.isEmpty)
    }

    /// The import's bytes changed after the person reviewed it: the Add validates again, sets it
    /// aside, and adds nothing.
    @Test func anImportChangedAfterReviewIsSetAsideAtTheAdd() async throws {
        let lab = try ShowcaseLab()
        let collection = try await lab.makeCollection("Field notes")
        let entry = try await lab.waitingNote("Reviewed as this")
        let record = lab.folders.shared.staging.root.appending(path: "pending/\(entry.id.staging)/record.json")
        var bytes = try Data(contentsOf: record)
        bytes[bytes.count - 3] ^= 0x01
        try bytes.write(to: record)

        await #expect(throws: ImportRejection.self) { _ = try await lab.add(entry, into: collection) }
        #expect(await lab.store.items(in: nil).isEmpty)
        let snapshot = await lab.folders.inbox.snapshot()
        #expect(snapshot.entries.isEmpty && snapshot.quarantined.count == 1)
    }

    // MARK: Step 3: duplicate state

    /// Two Adds of one import at once, as from two windows, store one item under one receipt.
    @Test func twoAddsOfOneImportAtOnceStoreOneItem() async throws {
        let lab = try ShowcaseLab()
        let collection = try await lab.makeCollection("Field notes")
        let entry = try await lab.waitingNote("Tapped twice")
        async let first = Self.result { () async throws(ImportRejection) -> ImportAdoption in try await lab.add(entry, into: collection) }
        async let second = Self.result { () async throws(ImportRejection) -> ImportAdoption in try await lab.add(entry, into: collection) }
        let results: [Result<ImportAdoption, ImportRejection>] = await [first, second]
        let receipts: [ActionReceipt] = results.compactMap { result in
            if case .success(let adoption) = result { adoption.receipt } else { nil }
        }
        #expect(!receipts.isEmpty)
        #expect(Set(receipts.map(\.operationID)).count == 1, "every Add that succeeded returned the one receipt")
        for case .failure(let rejection) in results {
            #expect(rejection == .notFound, "a losing Add finds the import already added")
        }
        #expect(await lab.store.items(in: collection).count == 1)
        #expect(await lab.folders.inbox.snapshot().entries.isEmpty)
        #expect(lab.ledger.liveGrants.isEmpty)
    }

    /// Finding: the same note pasted and added, then shared from another app and added to the same
    /// collection, derives the same request ID from a different adapter. The service refuses it as
    /// a reused request, so the Add says to share it again, which cannot help: the import stays
    /// waiting until the person removes it. Nothing is stored twice, and nothing else is blocked.
    @Test func theSameNoteFromPasteAndFromTheShareSheetIsStoredOnce() async throws {
        let lab = try ShowcaseLab()
        let collection = try await lab.makeCollection("Field notes")
        _ = await lab.folders.hostStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Harbor walk")]), via: .paste)
        let pasted = try #require(await lab.folders.inbox.snapshot().entries.first)
        let first = try await lab.add(pasted, into: collection)
        #expect(first.receipt.admitted.adapter == .appUI)

        _ = await lab.folders.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Harbor walk")]), via: .shareExtension)
        let shared = try #require(await lab.folders.inbox.snapshot().entries.first)
        #expect(shared.source == .shareExtension)
        let second = await Self.result { () async throws(ImportRejection) -> ImportAdoption in try await lab.add(shared, into: collection) }
        #expect(await lab.store.items(in: collection).count == 1, "never stored twice")
        let stillWaiting = await lab.folders.inbox.snapshot().entries.map(\.id)
        withKnownIssue("A cross-surface duplicate is refused as an identifier conflict instead of being recognized as already added.") {
            guard case .success(let adoption) = second else {
                Issue.record("the Add was refused: \(second)")
                return
            }
            #expect(adoption.isDuplicate && adoption.receipt == first.receipt)
            #expect(stillWaiting.isEmpty)
        }
        guard case .failure(let rejection) = second else { return }
        #expect(rejection == .identifierConflict, "today's behavior, recorded")
        #expect(stillWaiting == [shared.id], "the import keeps waiting until the person removes it")

        // It blocks nothing: the next share is added normally.
        _ = await lab.folders.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Tide tables")]), via: .shareExtension)
        let next = try #require(await lab.folders.inbox.snapshot().entries.first { $0.content == .text("Tide tables") })
        #expect(try await lab.add(next, into: collection).receipt.status == .committed)
    }

    // MARK: Step 3: reset without touching imported user data

    /// Reset Demo restores an edited sample and nothing else: added imports stay as they were, and
    /// imports still waiting keep waiting with their origins.
    @Test func resetDemoLeavesAddedAndWaitingImportsAlone() async throws {
        let lab = try ShowcaseLab()
        let seed = try ShareIngressShowcaseFile.load().seed
        _ = try await lab.confirm(.resetDemo(seed: seed), request: RequestID())
        let sample = try #require(seed.items.first)
        _ = try await lab.service.perform(OperationRequest(
            id: RequestID(), operation: .updateItem(id: sample.id, expected: .initial, changes: try ItemChanges(title: try EntityTitle("Edited sample"))),
            actor: .testAppUI
        ))

        let collection = try await lab.makeCollection("Field notes")
        _ = await lab.folders.hostStation.receive(ItemProviderAttachment.attachments(from: [Providers.link("https://example.org/tide-tables")]), via: .paste)
        _ = await lab.folders.shareStation.receive(ItemProviderAttachment.attachments(from: [
            Providers.text("Harbor walk"), try Providers.file(SyntheticMedia.bytes(128), type: .png, suggestedName: "Buoy", folder: lab.folders.folder),
            Providers.text("Still waiting"),
        ]), via: .shareExtension)
        for entry in await lab.folders.inbox.snapshot().entries where [.text("Harbor walk"), .link(URL(string: "https://example.org/tide-tables")!, title: nil)].contains(entry.content) {
            _ = try await lab.add(entry, into: collection)
        }
        let imported = await lab.store.items(in: collection)
        #expect(imported.count == 2)
        let waiting = await lab.folders.inbox.snapshot().entries

        let reset = try await lab.confirm(.resetDemo(seed: seed), request: RequestID())
        #expect(reset.changes.map(\.entity) == [.item(sample.id)])
        #expect(reset.removed.isEmpty)
        #expect(await lab.store.items(in: collection) == imported)
        #expect(await lab.store.collection(collection)?.isArchived == false)
        let stillWaiting = await lab.folders.inbox.snapshot().entries
        #expect(stillWaiting.map(\.id) == waiting.map(\.id))
        #expect(stillWaiting.map(\.origin) == waiting.map(\.origin))
        #expect(stillWaiting.map(\.content) == [.files([InboxFile(name: "Buoy.png", byteCount: 128)]), .text("Still waiting")])
    }

    // MARK: Helpers

    private static func result(_ body: () async throws(ImportRejection) -> ImportAdoption) async -> Result<ImportAdoption, ImportRejection> {
        do throws(ImportRejection) { return .success(try await body()) } catch { return .failure(error) }
    }
}

// MARK: - Support

extension ShowcaseLab {
    func makeCollection(_ title: String) async throws -> CollectionID {
        let id = CollectionID()
        _ = try await service.perform(OperationRequest(
            id: RequestID(), operation: .createCollection(draft: CollectionDraft(id: id, title: try EntityTitle(title))), actor: .testAppUI
        ))
        return id
    }

    /// Shares one note through the share extension's folder and returns its inbox entry.
    func waitingNote(_ text: String) async throws -> InboxEntry {
        let report = await folders.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text(text)]), via: .shareExtension)
        try #require(report.stagedCount == 1)
        return try #require(await folders.inbox.snapshot().entries.first { $0.content == .text(text) })
    }
}

/// Holds a coordinated write on a file, as a file provider does while it downloads the file, until
/// released. Coordinated reads of the file wait for it.
final class CoordinatedWriter: Sendable {
    private let finished = DispatchSemaphore(value: 0)
    private let holding = Mutex<[CheckedContinuation<Void, Never>]?>([])

    init(holding url: URL) {
        Thread.detachNewThread { [self] in
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &error) { _ in
                let waiters = self.holding.withLock { waiters in
                    defer { waiters = nil }
                    return waiters ?? []
                }
                waiters.forEach { $0.resume() }
                self.finished.wait()
            }
        }
    }

    func waitUntilHolding() async {
        await withCheckedContinuation { continuation in
            let resumeNow = holding.withLock { waiters -> Bool in
                guard waiters != nil else { return true }
                waiters?.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func release() { finished.signal() }
}

/// A grant clock a test moves forward.
final class SteppedGrantClock: GrantClock {
    private let offset = Mutex(Duration.zero)
    private let origin = ContinuousClock.now

    func now() -> ContinuousClock.Instant { origin + offset.withLock { $0 } }
    func advance(by duration: Duration) { offset.withLock { $0 += duration } }
}

/// `Fixtures/hostile/traversal-names.json`: the text cases. Cases given only as raw bytes cannot be
/// a provider's suggested name and are left to the staging tests.
struct TraversalNames: Decodable {
    struct Case: Decodable {
        let id: String
        let name: String?
        let expect: String
    }

    let cases: [Case]

    static func load() throws -> [Case] {
        try JSONDecoder().decode(TraversalNames.self, from: HostileFixtures.data("traversal-names.json")).cases
    }
}
