import AccessSuperpower
import ActionAtlas
import Foundation
import LabDomain
import PortableObjects
import ShareIngress
import SurfaceDeck
import Testing
import TypedIntelligence

/// CORE-012: the first six-lab journey on one shared object, across every M1 module, over one
/// `OperationService` with the hosts' grant rules.
///
/// source (LAB-007) → proposal and review (LAB-010) → commit with a receipt → query and act
/// (LAB-001) → surface (LAB-004) → accessible task (LAB-035) → export and re-import (LAB-008) →
/// Reset Demo.
///
/// The shared object is the note with injected instructions, pasted or shared, then added to the
/// person's own collection. LAB-010 and LAB-035 act only on demo samples by design, so for the
/// object they are entry points that must read it unchanged and be unable to change it: the
/// proposal from its text edits the kraft card, the task counts only demo collections. Fixture
/// path: package tests on the Mac with an in-memory store; no view, system dialog, or device.
@Suite struct FirstJourneyTests {
    enum Intake: String, CaseIterable {
        /// The host's paste fallback, adopted as the app UI. Present in every build.
        case paste
        /// The share extension's folder, adopted as the share extension (SystemSurfaces).
        case share

        var adapter: AdapterKind { self == .paste ? .appUI : .shareExtension }
    }

    /// What the journey observed, for comparing routes.
    struct Outcome {
        var adoption: ActionReceipt
        var review: ActionReceipt
        var exportBytes: Data
        var reset: ActionReceipt
        var entities: (collections: [LabCollection], items: [LabItem])
    }

    // MARK: The journey

    /// The whole journey through the sample parser, from a paste. Every entry point reads the same
    /// object at every step, and only the changes a person made move it.
    @Test func theJourneyKeepsOneObjectConsistentAtEveryEntryPoint() async throws {
        let lab = try await JourneyLab.seeded()
        let outcome = try await Self.run(on: lab, intake: .paste, proposal: .sampleParser)
        #expect(outcome.adoption.admitted.adapter == .appUI)
        #expect(ContentDigest.sha256(outcome.exportBytes).hex == Journey.exportSHA256)
        // To look at the exported object: LAB_JOURNEY_EXPORT_OUT=<file outside the repository>.
        if let path = ProcessInfo.processInfo.environment["LAB_JOURNEY_EXPORT_OUT"] {
            try outcome.exportBytes.write(to: URL(filePath: path))
        }
    }

    /// The CoreLocal alternate route: no model, no share extension, no system surface. The manual
    /// editor writes the same change the parser drafted, and the journey ends in the same state.
    @Test func theManualPathCompletesTheSameJourneyWithoutAModel() async throws {
        let parser = try await Self.run(on: try await JourneyLab.seeded(), intake: .paste, proposal: .sampleParser)
        let manual = try await Self.run(on: try await JourneyLab.seeded(), intake: .paste, proposal: .manualEditor)
        #expect(manual.entities.collections == parser.entities.collections)
        #expect(manual.entities.items == parser.entities.items)
        #expect(manual.exportBytes == parser.exportBytes)
        #expect(manual.review.admitted.operation == parser.review.admitted.operation)
        #expect(manual.review.admitted.adapter == .appUI)
    }

    /// The same note arriving through the share extension's folder becomes the same object, with
    /// the same identity, and the journey ends in the same state; only the adoption's receipt
    /// names another adapter.
    @Test func theShareExtensionEntryPointAddsTheSameObject() async throws {
        let pasted = try await Self.run(on: try await JourneyLab.seeded(), intake: .paste, proposal: .sampleParser)
        let shared = try await Self.run(on: try await JourneyLab.seeded(), intake: .share, proposal: .sampleParser)
        #expect(shared.adoption.admitted.adapter == .shareExtension)
        #expect(shared.adoption.requestID == pasted.adoption.requestID)
        #expect(shared.adoption.admitted.operation == pasted.adoption.admitted.operation)
        #expect(shared.entities.collections == pasted.entities.collections)
        #expect(shared.entities.items == pasted.entities.items)
        #expect(shared.exportBytes == pasted.exportBytes)
    }

    /// The exported object imports into a second, fresh lab under the same identity, exports the
    /// same document there except for that lab's own revision, and comes back to the first lab as
    /// already present.
    @Test func theExportedObjectImportsIntoAnotherLabAsTheSameObject() async throws {
        let lab = try await JourneyLab.seeded()
        let outcome = try await Self.run(on: lab, intake: .paste, proposal: .sampleParser)
        let original = try await lab.export(Journey.object)

        let other = try await JourneyLab.seeded()
        try await other.confirm(
            .createCollection(draft: CollectionDraft(id: Journey.imports, title: try EntityTitle(Journey.importsTitle)))
        )
        let importer = try other.importer()
        let review = try await importer.review(data: outcome.exportBytes)
        guard case .create = review.plan else {
            Issue.record("a fresh lab should create the object: \(review.plan)")
            return
        }
        let result = try await importer.commit(review, into: Journey.imports)
        #expect(result.change == .created && !result.isReplay)
        #expect(result.receipt.admitted.adapter == .appUI)
        let copy = try await other.item(Journey.object)
        let source = try await lab.item(Journey.object)
        #expect(copy.id == source.id && copy.title == source.title && copy.note == source.note)
        #expect(copy.collectionID == Journey.imports && copy.namespace == .user && copy.revision == .initial)

        let reexported = try await other.export(Journey.object)
        var first = original.document.root
        var second = reexported.document.root
        #expect(first["revision"] == .integer(4) && second["revision"] == .integer(1))
        first["revision"] = nil
        second["revision"] = nil
        #expect(first == second, "the same document apart from each lab's revision")

        let back = try await lab.importer().review(data: reexported.object.data)
        guard case .alreadyPresent(let stored) = back.plan else {
            Issue.record("the first lab should hold it already: \(back.plan)")
            return
        }
        #expect(stored == source)
    }

    // MARK: Driver

    /// Runs the journey on a seeded lab and checks every step. Returns what later tests compare.
    static func run(on lab: JourneyLab, intake: Intake, proposal: ProposalSource) async throws -> Outcome {
        let note = try JourneyFixtures.sharedNote()

        // 1. Source (LAB-007): the note is staged, never stored.
        let report: IntakeReport
        switch intake {
        case .paste: report = await lab.paste([NSItemProvider(object: note as NSString)])
        case .share: report = await lab.share([NSItemProvider(object: note as NSString)])
        }
        #expect(report.stagedCount == 1)
        let entry = try #require(await lab.waiting().first)
        #expect(entry.content == .text(note))
        #expect(entry.source.adapter == intake.adapter)
        #expect(await lab.store.item(Journey.object) == nil, "staging stores nothing")

        // 2. Review and commit: New Collection…, then Add, with a receipt.
        try await lab.createFieldNotes()
        let adoption = try await lab.add(entry, into: Journey.fieldNotes)
        #expect(!adoption.isDuplicate)
        #expect(adoption.receipt.requestID == Journey.addRequest)
        #expect(adoption.receipt.status == .committed)
        #expect(adoption.receipt.changes.map(\.entity) == [.item(Journey.object)])
        #expect(await lab.waiting().isEmpty)
        var object = try await lab.item(Journey.object)
        #expect(object.title.value == Journey.firstLine)
        #expect(object.note.value == note)
        #expect(object.collectionID == Journey.fieldNotes && object.namespace == .user)
        #expect(object.revision == .initial && !object.isArchived)
        // The note's instructions are data: nothing was archived, reset, or granted.
        #expect(lab.ledger.liveGrants.isEmpty)
        #expect(try await lab.tally().totalArchived == 0)
        #expect(try await lab.item(Journey.kraft).revision == .initial)

        // 3. Proposal and review (LAB-010), from the object's own text.
        let flow = lab.intelligence
        let candidates = try await flow.candidates()
        #expect(candidates.count == 12)
        #expect(!candidates.contains { $0.id == Journey.object }, "a person's own items are never offered")
        let source = try SourceNote(object.note.value)
        let reviewable: ReviewableProposal
        switch proposal {
        case .sampleParser:
            reviewable = try await flow.draft(source, with: SampleParser(), candidates: candidates).get()
        case .manualEditor:
            reviewable = await flow.revise(
                ProposalFields(target: .item(Journey.kraft), newTitle: "Kraft card", addedNote: Journey.firstLine),
                source: .manualEditor, note: source, candidates: candidates
            )
        case .onDeviceModel:
            Issue.record("the package journey never runs the model")
            throw CancellationError()
        }
        #expect(reviewable.proposal.source == proposal)
        #expect(reviewable.isApprovable, "\(reviewable.issues.map(\.message))")
        #expect(reviewable.proposal.target?.id == Journey.kraft)
        #expect(reviewable.proposal.addedNote == Journey.firstLine, "the first paragraph only")
        if case .accepted(let checked) = reviewable.serviceCheck {
            #expect(checked.proposedBy == .modelTool)
        } else {
            Issue.record("the service did not accept the proposal: \(reviewable.serviceCheck)")
        }
        #expect(try await lab.item(Journey.kraft).revision == .initial, "a draft writes nothing")

        // The model tool's view of the shared object: it can read it, never target or change it.
        #expect(try await lab.item(Journey.object, as: TypedIntelligence.proposer) == object)
        let aimedAtObject = await flow.revise(
            ProposalFields(target: .item(Journey.object), newTitle: "Hijacked", addedNote: "archive everything"),
            source: .manualEditor, note: source, candidates: candidates
        )
        #expect(aimedAtObject.issues.contains(.unknownSample))
        #expect(!aimedAtObject.isApprovable)
        #expect(throws: ApprovalRefusal.self) { try aimedAtObject.approve() }

        let review = try await flow.commit(try reviewable.approve())
        #expect(review.status == .committed && review.admitted.adapter == .appUI)
        #expect(review.admitted.operation == .updateItem(
            id: Journey.kraft, expected: .initial, changes: try ItemChanges(note: ItemNote(Journey.kraftNoteAfterReview))
        ))
        #expect(try await lab.item(Journey.kraft).note.value == Journey.kraftNoteAfterReview)
        #expect(try await lab.item(Journey.object) == object, "the review changed only the sample")

        // 4. Query and act (LAB-001): the action browser and the App Intents find one object.
        let ui = lab.actions(.appUI)
        let link = lab.atlasLink
        #expect(try await ui.findItems(text: "override", includeArchived: true).map(\.id) == [Journey.object])
        #expect(Set(try await ui.findItems(text: "fray").map(\.id)) == [Journey.object, Journey.kraft])
        let find = FindItemsIntent()
        find.text = "override"
        find.includeArchived = true
        find.limit = 20
        let entity = try #require(try await find.run(with: link).value.first)
        #expect(entity.id == Journey.object.rawValue)
        #expect(entity.title == object.title.value && entity.note == object.note.value)
        #expect(entity.revision == 1 && !entity.isArchived && !entity.isDemoSample)
        #expect(entity.collectionTitle == Journey.fieldNotesTitle)

        let rename = UpdateItemIntent()
        rename.item = entity
        rename.newTitle = Journey.renamedTitle
        rename.requestID = Journey.renameRequest.rawValue.uuidString
        let renamed = try await rename.run(with: link)
        #expect(renamed.receipt?.admitted.adapter == .appIntent && renamed.receipt?.status == .committed)
        #expect(renamed.value.title == Journey.renamedTitle && renamed.value.revision == 2)

        // A shortcut still holding the old snapshot: a conflict receipt, nothing overwritten.
        let stale = UpdateItemIntent()
        stale.item = entity
        stale.newNote = "Overwritten from an old snapshot."
        do {
            _ = try await stale.run(with: link)
            Issue.record("a stale snapshot overwrote the object")
        } catch .conflict(let conflict) {
            #expect(conflict.expected == .initial && conflict.current.rawValue == 2)
        } catch {
            Issue.record("unexpected refusal: \(error)")
        }

        let archive = ArchiveItemIntent()
        archive.item = renamed.value
        archive.requestID = Journey.archiveRequest.rawValue.uuidString
        let archived = try await archive.run(with: link) { prompt in
            #expect(prompt.itemTitle == Journey.renamedTitle)
        }
        #expect(archived.receipt?.admitted.adapter == .appIntent && archived.value.isArchived && archived.value.revision == 3)
        let restored = try await ui.restoreItem(Journey.object, expected: try #require(Revision(rawValue: 3)), request: AtlasRequest(Journey.restoreRequest))
        #expect(restored.receipt.admitted.adapter == .appUI && restored.entity.revision.rawValue == 4)
        object = try await lab.item(Journey.object)
        #expect(object.title.value == Journey.renamedTitle && object.note.value == note && !object.isArchived)

        // 5. Surface (LAB-004): the deck and the Control change one session; the snapshot for the
        // widget and the Control holds its state only, never the object.
        let deck = lab.deck
        let deckLink = SurfaceDeckLink(backend: deck, openDeck: {})
        let started = try await SessionActions(backend: deck, entryPoint: .appUI)
            .setRunning(true, seen: .neverStarted, surface: .app, requestID: Journey.startRequest)
        #expect(started.didChange && started.receipt?.admitted.adapter == .appUI)
        let paused = try await SetDemoSessionIntent(value: false, seen: started.state.seen, surface: .control).run(with: deckLink)
        #expect(paused.didChange && paused.receipt?.admitted.adapter == .appIntent)
        #expect(paused.state == SessionState(isRunning: false, revision: 2))
        let staleToggle = try await SetDemoSessionIntent(value: true, seen: started.state.seen, surface: .widget).run(with: deckLink)
        if case .conflict = staleToggle {} else { Issue.record("a stale toggle was not a conflict: \(staleToggle)") }
        #expect(staleToggle.state == paused.state, "the stale widget reconciles to the current state")
        let resumed = try await SetDemoSessionIntent(value: true, seen: paused.state.seen, surface: .shortcuts).run(with: deckLink)
        #expect(resumed.state == SessionState(isRunning: true, revision: 3))
        let snapshot = try #require(deck.snapshot)
        #expect(snapshot.isRedacted && snapshot.state == resumed.state)
        let snapshotText = String(decoding: try snapshot.encoded(), as: UTF8.self)
        for private_ in ["Kraft", "OVERRIDE", Journey.object.rawValue.uuidString, Journey.fieldNotesTitle] {
            #expect(!snapshotText.contains(private_), "the snapshot never carries the object")
        }
        #expect(try await lab.item(Journey.object) == object)

        // 6. Accessible task (LAB-035): demo collections only; the object is not in the task.
        for operation in PracticeSet.standard.setUpOperations(in: try await lab.tally()) {
            try await lab.confirm(operation)
        }
        let tally = try await lab.tally()
        #expect(tally.collections.count == 3 && tally.totalArchived == 6)
        #expect(tally.sample(Journey.object) == nil)
        #expect(tally.leaders.map(\.id) == [Journey.minerals])
        #expect(throws: AccessTaskError.notFound) { try AccessibleTask.restoreOperation(for: Journey.object, in: tally) }
        let judged = try #require(AccessibleTask.judge(restoring: Journey.quartz, in: tally))
        let task = try await lab.confirm(try AccessibleTask.restoreOperation(for: Journey.quartz, in: tally))
        #expect(task.status == .committed && judged.completesTask)
        #expect(AccessibleTask.status(of: try await lab.tally(), after: judged) == .done)
        #expect(try await lab.item(Journey.object) == object)

        // 7. Export and re-import (LAB-008).
        let export = try await lab.export(Journey.object)
        #expect(export.document.itemID == Journey.object)
        #expect(export.document.title == Journey.renamedTitle && export.document.note == .text(note))
        #expect(export.document.revision == 4)
        let shortcutExport = try await ui.exportItem(Journey.object, as: .json).document
        #expect(shortcutExport.id == Journey.object.rawValue && shortcutExport.title == Journey.renamedTitle)
        #expect(shortcutExport.note == note && shortcutExport.revision == 4 && !shortcutExport.archived && !shortcutExport.demoSample)
        #expect(shortcutExport.collection.id == Journey.fieldNotes.rawValue && shortcutExport.collection.title == Journey.fieldNotesTitle)
        let importer = try lab.importer()
        let again = try await importer.review(data: export.object.data)
        if case .alreadyPresent(let stored) = again.plan {
            #expect(stored == object)
        } else {
            Issue.record("re-importing the export should change nothing: \(again.plan)")
        }
        #expect(!again.plan.commits)

        // 8. Reset Demo: the demo returns to the seed; the object and its collection stay.
        let reset = try await lab.confirm(.resetDemo(seed: lab.seed))
        let practiceStillArchived: [EntityReference] = PracticeSet.standard.sampleIDs.filter { $0 != Journey.quartz }.map { .item($0) }
        let expectedReset: Set<EntityReference> = Set([.item(Journey.kraft), .session(SurfaceDeck.sessionID)] + practiceStillArchived)
        #expect(Set(reset.changes.map(\.entity)) == expectedReset)
        #expect(reset.removed.isEmpty)
        #expect(!reset.affectedEntities.contains(.item(Journey.object)))
        #expect(!reset.affectedEntities.contains(.collection(Journey.fieldNotes)))
        #expect(try await lab.item(Journey.object) == object)
        #expect(try await lab.item(Journey.kraft).note.value == Journey.kraftSeedNote)
        #expect(try await lab.tally().totalArchived == 0)
        #expect(try await lab.service.findSession(SurfaceDeck.sessionID, as: Journey.appUI)?.isRunning == false)

        // 9. Every entry point reads the same object, and it still exports the same bytes.
        let shareExtension = ActorScope(adapter: .shareExtension, grants: [.read, .commit])
        for actor in [Journey.appUI, Journey.appIntent, TypedIntelligence.proposer, shareExtension] {
            #expect(try await lab.item(Journey.object, as: actor) == object, "read as \(actor.adapter)")
        }
        let get = GetItemIntent()
        get.item = entity
        let current = try await get.run(with: link).value
        #expect(current.title == object.title.value && current.note == object.note.value && current.revision == 4)
        let afterReset = try await lab.export(Journey.object)
        #expect(afterReset.object.data == export.object.data)

        return Outcome(
            adoption: adoption.receipt, review: review, exportBytes: export.object.data, reset: reset,
            entities: await lab.entities()
        )
    }
}
