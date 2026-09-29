import Foundation
import LabDomain
import Testing

/// Holds `validatedRecord` until the test releases it, so a test can cancel an adoption at a
/// known point.
actor GatedInbox: StagingInbox {
    let inner: InMemoryStagingInbox
    private var entered: CheckedContinuation<Void, Never>?
    private var gate: CheckedContinuation<Void, Never>?
    private var hasEntered = false

    init(_ inner: InMemoryStagingInbox) { self.inner = inner }

    func validatedRecord(_ id: StagingID) async throws(ImportRejection) -> StagingRecord {
        hasEntered = true
        entered?.resume()
        entered = nil
        await withCheckedContinuation { gate = $0 }
        return try await inner.validatedRecord(id)
    }

    func markAdopted(_ id: StagingID) async throws(ImportRejection) {
        await inner.markAdopted(id)
    }

    func waitUntilEntered() async {
        if hasEntered { return }
        await withCheckedContinuation { entered = $0 }
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

/// CORE-006: adoption goes through the one operation service, needs a live grant for exactly that
/// change, is idempotent by content, and adopts nothing when cancelled or refused.
@Suite struct ImportAdoptionTests {
    @Test func anApprovedImportIsAdoptedThroughTheOperationService() async throws {
        let lab = GrantedLab()
        let inbox = try await lab.makeCollection("Inbox")
        let text = "Harbor walk\nBring the blue notebook.\tAnd a pencil."
        let id = try await lab.stageText(text)
        try lab.approve(into: inbox.id)

        let adoption = try await lab.adopter.adopt(id, into: inbox.id)
        #expect(!adoption.isDuplicate)
        #expect(adoption.receipt.status == .committed)
        #expect(adoption.receipt.admitted.adapter == .shareExtension)
        guard case .createItem(let draft) = adoption.receipt.admitted.operation else {
            Issue.record("adoption committed \(adoption.receipt.admitted.operation.kind)")
            return
        }
        let item = try await lab.service.findItem(draft.id, as: .appUI)
        #expect(item.collectionID == inbox.id)
        #expect(item.title == "Harbor walk")
        #expect(item.note.value == text)
        #expect(item.namespace == .user)
        #expect(await lab.inbox.waitingIDs.isEmpty)
    }

    @Test func aDuplicateImportIsIdempotent() async throws {
        let lab = GrantedLab()
        let inbox = try await lab.makeCollection("Inbox")
        let record = try StagingRecord(payload: .text("Same shared note"))
        #expect(await lab.inbox.stage(record) == .staged(record.id))
        #expect(await lab.inbox.stage(try StagingRecord(payload: .text("Same shared note"))) == .duplicate(record.id))
        try lab.approve(into: inbox.id)

        let first = try await lab.adopter.adopt(record.id, into: inbox.id)
        let commits = await lab.appliedCommits
        // Shared again later: staged again, adopted again, stored once.
        #expect(await lab.inbox.stage(try StagingRecord(payload: .text("Same shared note"))) == .staged(record.id))
        let second = try await lab.adopter.adopt(record.id, into: inbox.id)

        #expect(second.isDuplicate && !first.isDuplicate)
        #expect(second.receipt == first.receipt)
        #expect(await lab.appliedCommits == commits)
        let items = try await lab.service.findItems(ItemFilter(collectionID: inbox.id), as: .appUI)
        #expect(items.count == 1)
        #expect(await lab.inbox.waitingIDs.isEmpty)

        // The same content into another collection is a separate, deliberate item.
        let archive = try await lab.makeCollection("Archive")
        try lab.approve(into: archive.id)
        #expect(await lab.inbox.stage(record) == .staged(record.id))
        let elsewhere = try await lab.adopter.adopt(record.id, into: archive.id)
        #expect(!elsewhere.isDuplicate && elsewhere.receipt.requestID != first.receipt.requestID)
    }

    @Test func withoutApprovalNothingIsAdopted() async throws {
        let lab = GrantedLab()
        let inbox = try await lab.makeCollection()
        let id = try await lab.stageText("Needs a person to approve")
        let before = await lab.appliedCommits
        let refused = await rejection { () async throws(ImportRejection) in try await lab.adopter.adopt(id, into: inbox.id) }
        #expect(refused == .grantMissing)
        expectReadable(refused)
        #expect(await lab.appliedCommits == before)
        #expect(await lab.inbox.waitingIDs == [id])
    }

    @Test func anExpiredApprovalIsRefused() async throws {
        let lab = GrantedLab()
        let inbox = try await lab.makeCollection()
        let id = try await lab.stageText("Approved, then left too long")
        try lab.approve(into: inbox.id, lifetime: .seconds(10))
        lab.clock.advance(by: .seconds(11))
        let refused = await rejection { () async throws(ImportRejection) in try await lab.adopter.adopt(id, into: inbox.id) }
        #expect(refused == .grantExpired)
        #expect(try await lab.service.findItems(ItemFilter(collectionID: inbox.id), as: .appUI).isEmpty)
    }

    @Test func anApprovalForAnotherCollectionIsOutOfScope() async throws {
        let lab = GrantedLab()
        let approved = try await lab.makeCollection("Approved")
        let other = try await lab.makeCollection("Other")
        let id = try await lab.stageText("Approved for a different place")
        try lab.approve(into: approved.id)
        let refused = await rejection { () async throws(ImportRejection) in try await lab.adopter.adopt(id, into: other.id) }
        #expect(refused == .grantOutOfScope)
        #expect(try await lab.service.findItems(ItemFilter(collectionID: other.id), as: .appUI).isEmpty)
    }

    @Test func anApprovalThatLapsesBeforeTheCommitFailsAtTheCommit() async throws {
        let lab = GrantedLab()
        let inbox = try await lab.makeCollection()
        let id = try await lab.stageText("The approval lapses mid-adoption")
        try lab.approve(into: inbox.id, lifetime: .seconds(1))
        // Every clock reading from now on moves time two seconds: the adopter's own check passes,
        // and the policy's check inside `perform` finds the grant expired.
        lab.clock.setStepAfterRead(.seconds(2))
        let before = await lab.appliedCommits
        let refused = await rejection { () async throws(ImportRejection) in try await lab.adopter.adopt(id, into: inbox.id) }
        #expect(refused == .grantExpired)
        #expect(await lab.appliedCommits == before)
        #expect(lab.diagnostics.events.contains { $0.phase == "grant.check" && $0.category == .grantExpired })
    }

    @Test func aCancelledImportLeavesNoAdoptedObject() async throws {
        let lab = GrantedLab()
        let inbox = try await lab.makeCollection()
        let id = try await lab.stageText("Cancelled while being reviewed")
        try lab.approve(into: inbox.id)
        let gated = GatedInbox(lab.inbox)
        let adopter = ImportAdopter(service: lab.service, inbox: gated, ledger: lab.ledger)
        let before = await lab.appliedCommits

        let task = Task { () async throws -> ImportAdoption in try await adopter.adopt(id, into: inbox.id) }
        await gated.waitUntilEntered()
        task.cancel()
        await gated.release()
        let result = await task.result

        #expect(throws: ImportRejection.cancelled) { try result.get() }
        #expect(await lab.appliedCommits == before)
        #expect(try await lab.service.findItems(ItemFilter(collectionID: inbox.id), as: .appUI).isEmpty)
        #expect(await lab.inbox.waitingIDs == [id], "the record stays waiting for another try")

        // Nothing about the cancelled attempt blocks the next one.
        let adopted = try await lab.adopter.adopt(id, into: inbox.id)
        #expect(adopted.receipt.status == .committed && !adopted.isDuplicate)
    }

    @Test func anAlreadyCancelledTaskAdoptsNothing() async throws {
        let lab = GrantedLab()
        let inbox = try await lab.makeCollection()
        let id = try await lab.stageText("Cancelled before it began")
        try lab.approve(into: inbox.id)
        let task = Task { () async throws -> ImportAdoption in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await lab.adopter.adopt(id, into: inbox.id)
        }
        await #expect(throws: ImportRejection.cancelled) { try await task.value }
        #expect(try await lab.service.findItems(ItemFilter(collectionID: inbox.id), as: .appUI).isEmpty)
    }

    @Test func theOversizedNoteFixtureIsRefusedBeforeAdoption() async throws {
        let lab = GrantedLab()
        let inbox = try await lab.makeCollection()
        let id = try await lab.stageText(try HostileFixtures.text("oversized-note.txt"))
        try lab.approve(into: inbox.id)
        let refused = await rejection { () async throws(ImportRejection) in try await lab.adopter.adopt(id, into: inbox.id) }
        #expect(refused == .textTooLongForNote(limit: 2_000))
        expectReadable(refused)
        #expect(try await lab.service.findItems(ItemFilter(collectionID: inbox.id), as: .appUI).isEmpty)
    }

    @Test func filesAreCheckedButNotAdoptedYet() async throws {
        let lab = GrantedLab()
        let inbox = try await lab.makeCollection()
        let file = StagedFile(path: try StagedPath("photo.heic"), byteCount: 3, sha256: .sha256(Data("abc".utf8)))
        let record = try StagingRecord(payload: .files([file]))
        _ = await lab.inbox.stage(record)
        try lab.approve(into: inbox.id)
        let refused = await rejection { () async throws(ImportRejection) in try await lab.adopter.adopt(record.id, into: inbox.id) }
        #expect(refused == .attachmentsNotAdoptable)
        #expect(await lab.inbox.waitingIDs == [record.id])
    }

    @Test func anUnavailableDestinationIsRefused() async throws {
        let lab = GrantedLab()
        let archived = try await lab.makeCollection("Old")
        try lab.ledger.issue(for: .archiveCollection(id: archived.id, expected: .initial), to: .appUI)
        _ = try await lab.service.perform(OperationRequest(
            id: RequestID(), operation: .archiveCollection(id: archived.id, expected: .initial), actor: .appUI
        ))
        let missing = CollectionID()
        let id = try await lab.stageText("Nowhere to go")
        for destination in [archived.id, missing] {
            try lab.approve(into: destination)
            let refused = await rejection { () async throws(ImportRejection) in try await lab.adopter.adopt(id, into: destination) }
            #expect(refused == .destinationUnavailable)
        }
        #expect(await lab.inbox.waitingIDs == [id])
    }

    @Test func aDamagedRecordIsQuarantinedAndDoesNotBlockTheNextImport() async throws {
        let lab = GrantedLab()
        let inbox = try await lab.makeCollection()
        let forgedID = StagingID(rawValue: UUID())
        await lab.inbox.storeUnchecked(try HostileFixtures.data("forged-staging-record.json"), as: forgedID)
        let truncatedID = StagingID(rawValue: UUID())
        await lab.inbox.storeUnchecked(Data("{\"format\":".utf8), as: truncatedID)
        try lab.approve(into: inbox.id)

        let forged = await rejection { () async throws(ImportRejection) in try await lab.adopter.adopt(forgedID, into: inbox.id) }
        #expect(forged == .unknownRecordField)
        let truncated = await rejection { () async throws(ImportRejection) in try await lab.adopter.adopt(truncatedID, into: inbox.id) }
        #expect(truncated?.category == .malformedData)
        #expect(await lab.inbox.quarantined.map(\.id) == [forgedID, truncatedID])
        #expect(await lab.inbox.waitingIDs.isEmpty)

        let id = try await lab.stageText("The next valid import")
        #expect(try await lab.adopter.adopt(id, into: inbox.id).receipt.status == .committed)
    }

    @Test func aRecordStoredUnderAnotherContentsIDIsRefused() async throws {
        let lab = GrantedLab()
        let inbox = try await lab.makeCollection()
        let honest = try StagingRecord(payload: .text("Honest"))
        let swappedID = StagingID(rawValue: UUID())
        await lab.inbox.storeUnchecked(honest.encoded(), as: swappedID)
        try lab.approve(into: inbox.id)
        let refused = await rejection { () async throws(ImportRejection) in try await lab.adopter.adopt(swappedID, into: inbox.id) }
        #expect(refused == .digestMismatch)
    }

    @Test func linksAdoptWithTheirTitleOrHost() async throws {
        let lab = GrantedLab()
        let inbox = try await lab.makeCollection()
        try lab.approve(into: inbox.id)
        let titled = try StagingRecord(payload: .link(try #require(URL(string: "https://example.com/a")), title: "  A page\nsecond line"))
        let untitled = try StagingRecord(payload: .link(try #require(URL(string: "https://example.org/b?c=d")), title: nil))
        for record in [titled, untitled] { _ = await lab.inbox.stage(record) }

        let first = try await lab.adopter.adopt(titled.id, into: inbox.id)
        let second = try await lab.adopter.adopt(untitled.id, into: inbox.id)
        let items = try await [first, second].asyncMap { adoption in
            try await lab.service.findItem(ItemID(rawValue: adoption.receipt.changes[0].entity.rawID), as: .appUI)
        }
        #expect(items.map(\.title.value) == ["A page", "example.org"])
        #expect(items.map(\.note.value) == ["https://example.com/a", "https://example.org/b?c=d"])
    }

    @Test func aLongFirstLineBecomesAShortenedTitle() throws {
        let line = String(repeating: "word ", count: 40)
        let record = try StagingRecord(payload: .text("\n\n  \(line)\nrest"))
        guard case .createItem(let draft) = try ImportAdopter.operation(for: record, into: CollectionID()) else {
            Issue.record("expected a new item")
            return
        }
        #expect(draft.title.value.count == EntityTitle.maximumLength)
        #expect(draft.title.value.hasSuffix("…"))
        #expect(draft.note.value == "\n\n  \(line)\nrest")
    }
}

extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        for element in self { results.append(try await transform(element)) }
        return results
    }
}
