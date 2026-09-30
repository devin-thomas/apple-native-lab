import AccessSuperpower
import ActionAtlas
import FirstJourney
import Foundation
import LabDomain
import LabSupport
import PortableObjects
import ShareIngress
import SurfaceDeck
import Testing
import TypedIntelligence

/// CORE-012 step 2: the journey's failure cases on the shared object. Each must refuse with a
/// reason a person can read, change nothing it was not asked to, and leave the next step usable:
/// model unavailable, permission denied, duplicate import, stale state, cancellation, and a demo
/// reset while the person's own work is in progress. Fixture path, in-memory store.
@Suite struct FirstJourneyFailureTests {
    /// A seeded lab with the shared note pasted and added to Field notes, as after the journey's
    /// second step.
    static func labWithSharedObject() async throws -> (JourneyLab, LabItem) {
        let lab = try await JourneyLab.seeded()
        _ = await lab.paste([NSItemProvider(object: try JourneyFixtures.sharedNote() as NSString)])
        try await lab.createFieldNotes()
        let entry = try #require(await lab.waiting().first)
        _ = try await lab.add(entry, into: Journey.fieldNotes)
        return (lab, try await lab.item(Journey.object))
    }

    static func denial(_ operation: DomainOperation, as actor: ActorScope, in lab: JourneyLab) async -> AuthorizationDenial.Reason? {
        do {
            _ = try await lab.service.perform(OperationRequest(id: RequestID(), operation: operation, actor: actor))
            return nil
        } catch {
            if case .unauthorized(let denial) = error { return denial.reason }
            return nil
        }
    }

    // MARK: Model unavailable

    /// For every gate the probe can find closed, the model is not offered, the reason is named, and
    /// the journey's review step completes through the manual editor with the same change.
    @Test(arguments: [
        LanguageModelReading(availability: .deviceNotEligible, supportsCurrentLocale: nil, localeIdentifier: "en_US"),
        LanguageModelReading(availability: .appleIntelligenceNotEnabled, supportsCurrentLocale: nil, localeIdentifier: "en_US"),
        LanguageModelReading(availability: .modelNotReady, supportsCurrentLocale: true, localeIdentifier: "en_US"),
        LanguageModelReading(availability: .available, supportsCurrentLocale: false, localeIdentifier: "en_US"),
        LanguageModelReading(availability: .notCompiled, supportsCurrentLocale: nil, localeIdentifier: "en_US"),
    ])
    func withTheModelUnavailableTheManualEditorCompletesTheReview(reading: LanguageModelReading) async throws {
        let readiness = await ModelReadiness.probe(CapabilityRegistry(platform: .macOS, source: NoModelDevice(reading: reading)))
        #expect(readiness.route == .fallback)
        let explanation = try #require(readiness.explanation)
        #expect(!explanation.isEmpty)
        #expect(readiness.fallback.summary.contains("sample parser"))

        let (lab, object) = try await Self.labWithSharedObject()
        let flow = lab.intelligence
        let candidates = try await flow.candidates()
        let reviewable = await flow.revise(
            ProposalFields(target: .item(Journey.kraft), newTitle: "Kraft card", addedNote: Journey.firstLine),
            source: .manualEditor, note: try SourceNote(object.note.value), candidates: candidates
        )
        let receipt = try await flow.commit(try reviewable.approve())
        #expect(receipt.admitted.adapter == .appUI && receipt.status == .committed)
        #expect(try await lab.item(Journey.kraft).note.value == Journey.kraftNoteAfterReview)
        #expect(try await lab.item(Journey.object) == object)
    }

    /// The model was offered but failed while drafting, for each way a request can fail after the
    /// probe passed. Each failure names itself in a sentence that says what to do next, proposes
    /// and stores nothing, and the manual editor still completes the review.
    @Test(arguments: [
        ExtractionFailure.modelUnavailable(.modelNotReady), .malformedOutput, .refused, .unsupportedLanguage,
        .contextTooLarge, .busy, .timedOut(limit: .seconds(30)), .other,
    ])
    func aModelThatFailsWhileDraftingLeavesTheManualEditor(failure: ExtractionFailure) async throws {
        let (lab, object) = try await Self.labWithSharedObject()
        let flow = lab.intelligence
        let candidates = try await flow.candidates()
        let source = try SourceNote(object.note.value)
        let drafted = await flow.draft(source, with: FailingModel(failure: failure), candidates: candidates)
        guard case .failure(let reported) = drafted else {
            Issue.record("a failed model proposed something")
            return
        }
        #expect(reported == failure)
        #expect(!reported.message.isEmpty && reported.message.hasSuffix("."))
        #expect(try await lab.item(Journey.kraft).revision == .initial)

        let reviewable = await flow.revise(
            ProposalFields(target: .item(Journey.kraft), newTitle: "Kraft card", addedNote: Journey.firstLine),
            source: .manualEditor, note: source, candidates: candidates
        )
        let receipt = try await flow.commit(try reviewable.approve())
        #expect(receipt.status == .committed && receipt.admitted.adapter == .appUI)
        #expect(try await lab.item(Journey.kraft).note.value == Journey.kraftNoteAfterReview)
        #expect(try await lab.item(Journey.object) == object)
    }

    // MARK: Permission denied

    /// Every entry point that may not change the shared object is refused by its ceiling or its
    /// missing grant, records nothing, and says why.
    @Test func entryPointsWithoutPermissionChangeNothing() async throws {
        let (lab, object) = try await Self.labWithSharedObject()
        let rename = DomainOperation.updateItem(id: object.id, expected: object.revision, changes: try ItemChanges(title: EntityTitle("Hijacked")))
        let archive = DomainOperation.archiveItem(id: object.id, expected: object.revision)
        let reset = DomainOperation.resetDemo(seed: lab.seed)
        let shareExtension = ActorScope(adapter: .shareExtension, grants: [.read, .commit])

        // The model tool may read and propose, never commit (ADR-007, ADR-011).
        #expect(await Self.denial(rename, as: TypedIntelligence.proposer, in: lab) == .outsideAdapterCeiling)
        #expect(await Self.denial(archive, as: TypedIntelligence.proposer, in: lab) == .outsideAdapterCeiling)
        #expect(await Self.denial(reset, as: TypedIntelligence.proposer, in: lab) == .outsideAdapterCeiling)
        // Shared content cannot destroy data, even with a grant for it.
        #expect(await Self.denial(archive, as: shareExtension, in: lab) == .outsideAdapterCeiling)
        #expect(await Self.denial(reset, as: shareExtension, in: lab) == .outsideAdapterCeiling)
        #expect(throws: GrantError.self) { try lab.ledger.issue(for: archive, to: .shareExtension) }
        // An App Intent without the system's confirmation, or the app without a control press.
        #expect(await Self.denial(archive, as: Journey.appIntent, in: lab) == .deniedByPolicy)
        #expect(await Self.denial(reset, as: Journey.appUI, in: lab) == .deniedByPolicy)

        let request = RequestID()
        do {
            _ = try await lab.atlas.commit(archive, requestID: request, authority: .intent(nil), names: [:])
            Issue.record("an intent archived without the confirmation")
        } catch {
            #expect(!error.message.isEmpty)
        }
        #expect(await lab.store.receipt(for: request) == nil)
        #expect(try await lab.item(Journey.object) == object)
        #expect(try await lab.tally().totalArchived == 0)

        // An import without a person's Add has no grant; into a demo collection it has nowhere to go.
        _ = await lab.paste([NSItemProvider(object: "Second note" as NSString)])
        let waiting = try #require(await lab.waiting().first)
        do {
            _ = try await ImportAdopter(service: lab.service, inbox: lab.host.staging, ledger: lab.ledger, adapter: .appUI)
                .adopt(waiting.id.staging, into: Journey.fieldNotes)
            Issue.record("an import was added without the Add")
        } catch {
            #expect(error == .grantMissing && !error.userMessage.isEmpty)
        }
        do {
            _ = try await lab.add(waiting, into: Journey.papers)
            Issue.record("an import was added to a demo collection")
        } catch {
            #expect(error == .destinationUnavailable && !error.userMessage.isEmpty)
        }
        #expect(await lab.waiting().map(\.id) == [waiting.id], "the refused import keeps waiting")
        #expect(try await lab.add(waiting, into: Journey.fieldNotes).receipt.status == .committed, "and the next Add works")
    }

    // MARK: Duplicate import

    /// However often the same object arrives, it is one item: a second paste while it waits, a
    /// paste after it was added, its export imported again, and two reviews committed together.
    @Test func duplicateImportsNeverDuplicateTheObject() async throws {
        let (lab, object) = try await Self.labWithSharedObject()
        let note = try JourneyFixtures.sharedNote()

        // Pasted again after it was added: Add returns the first receipt.
        _ = await lab.paste([NSItemProvider(object: note as NSString)])
        let again = try #require(await lab.waiting().first)
        // Pasted a third time while that copy waits: the intake recognizes it.
        let third = await lab.paste([NSItemProvider(object: note as NSString)])
        #expect(third.duplicateCount == 1 && third.stagedCount == 0)
        let repeated = try await lab.add(again, into: Journey.fieldNotes)
        #expect(repeated.isDuplicate && repeated.receipt.requestID == Journey.addRequest)
        #expect(await lab.store.items(in: Journey.fieldNotes).count == 1)

        // Its export, reviewed twice in two importers and committed from both into another lab.
        let bytes = try await lab.export(Journey.object).object.data
        let other = try await JourneyLab.seeded()
        try await other.confirm(.createCollection(draft: CollectionDraft(id: Journey.imports, title: try EntityTitle(Journey.importsTitle))))
        let firstWindow = try PortableObjectsImporter(backend: other.portable, stagingRoot: other.folder.appending(path: "window-1"))
        let secondWindow = try PortableObjectsImporter(backend: other.portable, stagingRoot: other.folder.appending(path: "window-2"))
        let firstReview = try await firstWindow.review(data: bytes)
        let secondReview = try await secondWindow.review(data: bytes)
        let first = try await firstWindow.commit(firstReview, into: Journey.imports)
        let second = try await secondWindow.commit(secondReview, into: Journey.imports)
        #expect(!first.isReplay && second.isReplay && second.receipt == first.receipt)
        #expect(await other.store.items(in: Journey.imports).map(\.id) == [Journey.object])

        // Back in the first lab it is already present, and nothing commits.
        let back = try await lab.importer().review(data: bytes)
        #expect(!back.plan.commits)
        #expect(try await lab.item(Journey.object) == object)
    }

    /// The same note shared after it was pasted and added derives the same object, and is not
    /// stored twice. It is refused as an identifier conflict rather than recognized as already
    /// added: LAB-007-B's recorded known issue, whose sentence advises sharing again.
    @Test func theSameNoteSharedAfterItWasPastedIsNotStoredTwice() async throws {
        let (lab, object) = try await Self.labWithSharedObject()
        _ = try await lab.share([NSItemProvider(object: try JourneyFixtures.sharedNote() as NSString)])
        let shared = try #require(await lab.waiting().first)
        #expect(shared.source == .shareExtension)
        do {
            _ = try await lab.add(shared, into: Journey.fieldNotes)
            Issue.record("the cross-entry duplicate was accepted; update LAB-007-B's known issue")
        } catch {
            #expect(error == .identifierConflict)
            #expect(error.userMessage == "This import conflicts with an earlier request. Share it again.")
        }
        #expect(await lab.store.items(in: Journey.fieldNotes).count == 1)
        #expect(try await lab.item(Journey.object) == object)
        #expect(await lab.waiting().map(\.id) == [shared.id], "it waits until the person removes it")
        try await lab.inbox.discard(shared.id)
        #expect(await lab.waiting().isEmpty)
    }

    // MARK: Stale state

    /// A decision made from an old view of the object or the sample never overwrites what changed:
    /// the review's Apply, an object re-import, and the task's restore each leave a conflict or a
    /// refusal and change nothing.
    @Test func staleDecisionsChangeNothing() async throws {
        let (lab, object) = try await Self.labWithSharedObject()
        let link = lab.atlasLink

        // The review was approved, then the kraft card was renamed through Shortcuts.
        let flow = lab.intelligence
        let draft = try await flow.draft(try SourceNote(object.note.value), with: SampleParser(), candidates: try await flow.candidates()).get()
        let approval = try draft.approve()
        let kraftEntity = try #require(try await lab.entity(Journey.kraft))
        let rename = UpdateItemIntent()
        rename.item = kraftEntity
        rename.newTitle = "Kraft card (worn)"
        _ = try await rename.run(with: link)
        let renamedKraft = try await lab.item(Journey.kraft)
        let applied = try await flow.commit(approval)
        #expect(applied.conflict != nil && applied.changes.isEmpty)
        #expect(try await lab.item(Journey.kraft) == renamedKraft)

        // A reviewed edit of the object, stale because the object changed during the review.
        var root = try await lab.export(Journey.object).document.root
        root["title"] = .string("Edited elsewhere")
        let edited = try LabDocument(validating: .object(root)).encoded()
        let importer = try lab.importer()
        let review = try await importer.review(data: edited)
        guard case .differs = review.plan else {
            Issue.record("the edited copy should differ: \(review.plan)")
            return
        }
        let objectEntity = try #require(try await lab.entity(Journey.object))
        let objectRename = UpdateItemIntent()
        objectRename.item = objectEntity
        objectRename.newTitle = Journey.renamedTitle
        _ = try await objectRename.run(with: link)
        let current = try await lab.item(Journey.object)
        do {
            _ = try await importer.commit(review)
            Issue.record("a stale import overwrote the object")
        } catch {
            #expect(error == .stateChanged && !error.userMessage.isEmpty)
        }
        #expect(try await lab.item(Journey.object) == current)

        // The task's restore from a chart read before another window restored the sample.
        for operation in PracticeSet.standard.setUpOperations(in: try await lab.tally()) { try await lab.confirm(operation) }
        let seen = try await lab.tally()
        let quartz = try #require(seen.sample(Journey.quartz)?.sample)
        try await lab.confirm(.restoreItem(id: quartz.id, expected: quartz.revision))
        let restoredElsewhere = try await lab.item(Journey.quartz)
        let taskRestore = try await lab.confirm(try AccessibleTask.restoreOperation(for: Journey.quartz, in: seen))
        #expect(taskRestore.conflict != nil)
        #expect(try await lab.item(Journey.quartz) == restoredElsewhere)
        #expect(try await lab.item(Journey.object) == current)
    }

    // MARK: Cancellation

    /// A cancel at any step stops before its commit or keeps only what had committed, and the
    /// same step works afterwards.
    @Test(.timeLimit(.minutes(1)))
    func cancellingAnyStepLeavesNothingHalfDone() async throws {
        let lab = try await JourneyLab.seeded()
        let note = try JourneyFixtures.sharedNote()

        // The intake, while a shared photo is still downloading.
        let download = StalledDownload()
        let intake = Task { await lab.paste([NSItemProvider(object: note as NSString), download.provider]) }
        await download.waitUntilStarted()
        intake.cancel()
        let cancelled = await intake.value
        #expect(cancelled.wasCancelled && cancelled.summary == "The import was cancelled. Nothing from it was kept.")
        #expect(await lab.waiting().isEmpty)
        for _ in 0..<100 where !download.wasCancelled { try await Task.sleep(for: .milliseconds(10)) }
        #expect(download.wasCancelled)

        // The Add.
        _ = await lab.paste([NSItemProvider(object: note as NSString)])
        try await lab.createFieldNotes()
        let entry = try #require(await lab.waiting().first)
        let cancelledAdd = await Task { () -> ImportRejection? in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await lab.add(entry, into: Journey.fieldNotes); return nil } catch let error as ImportRejection { return error } catch { return nil }
        }.value
        #expect(cancelledAdd == .cancelled)
        #expect(await lab.store.item(Journey.object) == nil)
        #expect(await lab.waiting().map(\.id) == [entry.id])
        #expect(try await lab.add(entry, into: Journey.fieldNotes).receipt.status == .committed)
        let object = try await lab.item(Journey.object)

        // The draft, before the extractor answers.
        let flow = lab.intelligence
        let candidates = try await flow.candidates()
        let drafting = Task { await flow.draft(try! SourceNote(object.note.value), with: WaitingExtractor(), candidates: candidates) }
        try await Task.sleep(for: .milliseconds(50))
        drafting.cancel()
        if case .failure(let failure) = await drafting.value {
            #expect(failure == .cancelled && !failure.message.isEmpty)
        } else {
            Issue.record("a cancelled draft proposed something")
        }
        #expect(try await lab.item(Journey.kraft).revision == .initial)

        // The system's confirmation, declined.
        let archive = ArchiveItemIntent()
        archive.item = try #require(try await lab.entity(Journey.object))
        let request = RequestID()
        archive.requestID = request.rawValue.uuidString
        await #expect(throws: CancellationError.self) {
            _ = try await archive.run(with: lab.atlasLink) { _ in throw CancellationError() }
        }
        #expect(await lab.store.receipt(for: request) == nil)
        #expect(try await lab.item(Journey.object) == object)

        // Set Up Practice, stopped after its first commit: that one keeps its receipt.
        let operations = PracticeSet.standard.setUpOperations(in: try await lab.tally())
        let run = try await Task {
            try await PracticeRun.perform(operations) { operation in
                let receipt = try await lab.confirm(operation)
                withUnsafeCurrentTask { $0?.cancel() }
                return receipt
            }
        }.value
        #expect(run.wasCancelled && run.receipts.count == 1)
        #expect(try await lab.tally().totalArchived == 1)

        // An object import, cancelled at its commit, then committed once.
        let other = try await JourneyLab.seeded()
        try await other.confirm(.createCollection(draft: CollectionDraft(id: Journey.imports, title: try EntityTitle(Journey.importsTitle))))
        let importer = try other.importer()
        let review = try await importer.review(data: try await lab.export(Journey.object).object.data)
        let cancelledImport = await Task { () -> PortableObjectError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await importer.commit(review, into: Journey.imports); return nil } catch let error as PortableObjectError { return error } catch { return nil }
        }.value
        #expect(cancelledImport == .cancelled)
        #expect(await other.store.item(Journey.object) == nil)
        let committed = try await importer.commit(try await importer.review(data: try await lab.export(Journey.object).object.data), into: Journey.imports)
        #expect(committed.change == .created)
        #expect(try await lab.item(Journey.object) == object)
    }

    // MARK: Demo reset with the person's work in progress

    /// Reset Demo while the person has an added object, an import still waiting, an object review
    /// open, the practice set up, and the session running: only the demo changes, and the waiting
    /// import and the open review still complete afterwards as the person's own.
    @Test func resetDemoMidJourneyPreservesThePersonsData() async throws {
        let (lab, object) = try await Self.labWithSharedObject()
        _ = await lab.paste([NSItemProvider(object: "Still waiting\nA second field note." as NSString)])
        let waiting = try #require(await lab.waiting().first)
        let importer = try lab.importer()
        let review = try await importer.review(data: try #require(PortableSample.data))
        guard case .create = review.plan else {
            Issue.record("the sample is new to this lab: \(review.plan)")
            return
        }
        for operation in PracticeSet.standard.setUpOperations(in: try await lab.tally()) { try await lab.confirm(operation) }
        _ = try await SessionActions(backend: lab.deck, entryPoint: .appUI).setRunning(true, seen: .neverStarted, surface: .app)
        let flow = lab.intelligence
        let draft = try await flow.draft(try SourceNote(object.note.value), with: SampleParser(), candidates: try await flow.candidates()).get()
        _ = try await flow.commit(try draft.approve())

        let reset = try await lab.confirm(.resetDemo(seed: lab.seed))
        #expect(reset.removed.isEmpty)
        #expect(!reset.affectedEntities.contains(.item(Journey.object)) && !reset.affectedEntities.contains(.collection(Journey.fieldNotes)))
        #expect(try await lab.item(Journey.object) == object)
        #expect(try await lab.tally().totalArchived == 0)
        #expect(try await lab.item(Journey.kraft).note.value == Journey.kraftSeedNote)
        #expect(try await lab.service.findSession(SurfaceDeck.sessionID, as: Journey.appUI)?.isRunning == false)

        #expect(await lab.waiting().map(\.id) == [waiting.id], "the waiting import still waits")
        let added = try await lab.add(waiting, into: Journey.fieldNotes)
        #expect(added.receipt.status == .committed)
        let imported = try await importer.commit(review, into: Journey.fieldNotes)
        #expect(imported.change == .created && imported.item?.namespace == .user)
        #expect(await lab.store.items(in: Journey.fieldNotes).count == 3)
    }

    // MARK: Optional features that are not there

    /// An entry point whose backend is missing (the store never opened, or an intent ran before
    /// the app connected it) refuses with a sentence a person can act on, and nothing changes.
    @Test func unconnectedEntryPointsRefuseWithAReason() async throws {
        let get = GetItemIntent()
        let (lab, object) = try await Self.labWithSharedObject()
        get.item = try #require(try await lab.entity(Journey.object))
        do {
            _ = try await get.run(with: .unavailable)
            Issue.record("an unconnected intent read the store")
        } catch {
            #expect(error.message.contains("Open Native Lab"))
        }
        do {
            _ = try await SetDemoSessionIntent(value: true, seen: .neverStarted, surface: .control).run(with: .unavailable)
            Issue.record("an unconnected Control changed the session")
        } catch {
            #expect(error.message.contains("Open Native Lab"))
        }
        // A surface that finds no snapshot, or a damaged one, shows its placeholder.
        #expect(SessionSnapshot.decode(Data("{\"format\":\"something-else\"}".utf8)) == nil)
        #expect(try await lab.item(Journey.object) == object)
        #expect(try await lab.service.findSession(SurfaceDeck.sessionID, as: Journey.appUI) == nil)
    }
}

/// The on-device model, offered, failing a request as given.
struct FailingModel: NoteExtractor {
    let source = ProposalSource.onDeviceModel
    let failure: ExtractionFailure

    func extract(_ request: ExtractionRequest) async throws(ExtractionFailure) -> ExtractionDraft {
        throw failure
    }
}

/// A device whose language model reads as given. Nothing else is measured.
struct NoModelDevice: CapabilitySource {
    let reading: LanguageModelReading
    var isSimulator: Bool { false }
    func permissionStatus(_ permission: PermissionKind) -> PermissionStatus { .notReadable }
    func hasCaptureDevice(_ kind: CaptureDeviceKind) -> Bool? { nil }
    func speechTranscription() async -> SpeechTranscriptionReading {
        SpeechTranscriptionReading(transcriberAvailable: nil, localeIdentifier: "en_US", asset: .unknown)
    }
    func languageModel() -> LanguageModelReading { reading }
    func worldTracking() -> WorldTrackingReading? { nil }
    func ultraWideband() -> UltraWidebandReading? { nil }
    func entitlement(_ key: String) -> EntitlementReading { .notReadable }
    func declaresPurposeString(_ key: String) -> Bool { false }
}
