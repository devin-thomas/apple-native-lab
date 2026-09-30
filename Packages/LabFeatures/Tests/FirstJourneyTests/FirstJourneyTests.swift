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

    /// The build the journey runs in and the entry points it uses. CoreLocal is the app, its App
    /// Intents, and Shortcuts (BUILD_AND_DISTRIBUTION); SystemSurfaces adds the share extension,
    /// the widget, and the Control.
    struct Route: CustomTestStringConvertible {
        let name: String
        let intake: Intake
        let proposal: ProposalSource
        let systemSurfaces: Bool
        /// Where the session is paused, toggled from a stale view, and resumed after the deck in
        /// the app starts it.
        let pause: SessionSurface
        let staleToggle: SessionSurface
        let resume: SessionSurface

        var testDescription: String { name }

        /// Every adapter this build has that reads items.
        var readers: [ActorScope] {
            [Journey.appUI, Journey.appIntent, TypedIntelligence.proposer]
                + (systemSurfaces ? [ActorScope(adapter: .shareExtension, grants: [.read, .commit])] : [])
        }

        static let pastedWithSurfaces = Route(
            name: "SystemSurfaces, pasted, sample parser", intake: .paste, proposal: .sampleParser, systemSurfaces: true,
            pause: .control, staleToggle: .widget, resume: .shortcuts
        )
        static let sharedWithSurfaces = Route(
            name: "SystemSurfaces, shared, sample parser", intake: .share, proposal: .sampleParser, systemSurfaces: true,
            pause: .control, staleToggle: .widget, resume: .shortcuts
        )
        /// No model, no share extension, no widget or Control: paste, the manual editor, the app,
        /// and Shortcuts.
        static let coreLocal = Route(
            name: "CoreLocal, pasted, manual editor", intake: .paste, proposal: .manualEditor, systemSurfaces: false,
            pause: .shortcuts, staleToggle: .shortcuts, resume: .shortcuts
        )
    }

    /// What the journey observed, for comparing routes.
    struct Outcome {
        var adoption: ActionReceipt
        var review: ActionReceipt
        var exportBytes: Data
        var reset: ActionReceipt
        var entities: (collections: [LabCollection], items: [LabItem])
        /// Every receipt of a change, in order.
        var receipts: [ActionReceipt]
        /// The steps after which every entry point was read and compared with the store.
        var checkedSteps: [String]
    }

    // MARK: The journey

    /// The whole journey through the sample parser, from a paste. After every step, every entry
    /// point reads the same object the store holds, and only the changes a person made move it.
    @Test func theJourneyKeepsOneObjectConsistentAtEveryEntryPoint() async throws {
        let lab = try await JourneyLab.seeded()
        let outcome = try await Self.run(on: lab, route: .pastedWithSurfaces)
        #expect(outcome.adoption.admitted.adapter == .appUI)
        #expect(ContentDigest.sha256(outcome.exportBytes).hex == Journey.exportSHA256)
        #expect(outcome.checkedSteps == ["add", "review", "rename", "stale-update", "archive", "restore", "session", "task", "export", "reset", "get"])
        #expect(outcome.receipts.allSatisfy { $0.status == .committed })
        // To look at the exported object: LAB_JOURNEY_EXPORT_OUT=<file outside the repository>.
        if let path = ProcessInfo.processInfo.environment["LAB_JOURNEY_EXPORT_OUT"] {
            try outcome.exportBytes.write(to: URL(filePath: path))
        }
    }

    /// The CoreLocal alternate route: no model, no share extension, no App Group, no widget or
    /// Control. The model probe finds nothing and routes to the fallback; the manual editor
    /// writes the same change the parser drafted; and the journey ends in the same state, with
    /// every change committed by the app or an App Intent.
    @Test func theManualPathCompletesTheSameJourneyWithoutAModel() async throws {
        let readiness = await ModelReadiness.probe(CapabilityRegistry(
            platform: .iOS,
            source: NoModelDevice(reading: LanguageModelReading(availability: .notCompiled, supportsCurrentLocale: nil, localeIdentifier: "en_US"))
        ))
        #expect(readiness.route == .fallback)

        let parser = try await Self.run(on: try await JourneyLab.seeded(), route: .pastedWithSurfaces)
        let coreLocal = try await JourneyLab.seeded(shareExtension: false)
        let manual = try await Self.run(on: coreLocal, route: .coreLocal)
        #expect(manual.entities.collections == parser.entities.collections)
        #expect(manual.entities.items == parser.entities.items)
        #expect(manual.exportBytes == parser.exportBytes)
        #expect(manual.review.admitted.operation == parser.review.admitted.operation)
        #expect(manual.review.admitted.adapter == .appUI)
        #expect(manual.receipts.count == parser.receipts.count)
        #expect(manual.receipts.allSatisfy { $0.status == .committed })
        #expect(Set(manual.receipts.map(\.admitted.adapter)) == [.appUI, .appIntent], "only the app and its App Intents changed anything")
        #expect(await coreLocal.inbox.snapshot().entries.isEmpty)
    }

    /// The showcase script (`Fixtures/showcase/first-journey/`) that `Packages/LabDemo` replays on
    /// SQLite as evidence is exactly this journey's changes: after its first Reset Demo, which
    /// `JourneyLab.seeded()` also makes, every change step is the operation the journey committed,
    /// in order, under the same request ID wherever the journey fixes one. LabFeatures does not
    /// depend on LabDemo, so the script is read as plain JSON; a step kind this test does not map
    /// fails it.
    @Test func theShowcaseScriptIsExactlyTheJourneysChanges() async throws {
        let lab = try await JourneyLab.seeded()
        let outcome = try await Self.run(on: lab, route: .pastedWithSurfaces)
        let steps = try ShowcaseScript.changes(seed: lab.seed)
        try #require(steps.first?.operation == .resetDemo(seed: lab.seed))
        let scripted = steps.dropFirst()
        #expect(scripted.count == outcome.receipts.count)
        for (step, receipt) in zip(scripted, outcome.receipts) {
            #expect(receipt.admitted.operation == step.operation, "\(step.id)")
        }
        let fixed = [
            Journey.createFieldNotes, Journey.addRequest, Journey.renameRequest, Journey.archiveRequest,
            Journey.restoreRequest, Journey.startRequest,
        ]
        let journeyRequests = Set(outcome.receipts.map(\.requestID))
        for request in fixed {
            #expect(journeyRequests.contains(request) && scripted.contains { $0.request == request }, "\(request)")
        }
    }

    /// Nothing the journey runs can reach a network or a cloud model: no URL loading, sockets,
    /// CloudKit, Private Cloud Compute, or web view in the six modules, the domain, staging, and
    /// store packages, or the host folders that present the journey. The on-device model is the
    /// only model, and the manual route never calls it.
    @Test func theJourneysCodeHasNoNetworkOrCloudRoute() throws {
        let forbidden = [
            "PrivateCloudCompute", "URLSession", "URLRequest", "NWConnection", "NWBrowser", "NWListener", "import Network",
            "import CloudKit", "CKContainer", "WebSocket", "WKWebView", "SFSafari", "openURL", "NSWorkspace.shared.open",
        ]
        let folders = [
            "Packages/LabFeatures/Sources/ActionAtlas", "Packages/LabFeatures/Sources/SurfaceDeck",
            "Packages/LabFeatures/Sources/ShareIngress", "Packages/LabFeatures/Sources/PortableObjects",
            "Packages/LabFeatures/Sources/TypedIntelligence", "Packages/LabFeatures/Sources/AccessSuperpower",
            "Packages/LabDomain/Sources", "Packages/LabStaging/Sources", "Packages/LabStore/Sources",
            "Apps/Shared/ActionAtlas", "Apps/Shared/SurfaceDeck", "Apps/Shared/ShareInbox", "Apps/Shared/PortableObjects",
            "Apps/Shared/Intelligence", "Apps/Shared/AccessSuperpower", "Apps/Shared/Library", "Apps/Shared/Collection",
            "Apps/Shared/Receipts",
        ]
        var searched = 0
        for folder in folders {
            let root = JourneyFixtures.root.appending(path: folder, directoryHint: .isDirectory)
            let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
            #expect(!files.isEmpty, "\(folder) has sources")
            for file in files {
                let source = try String(contentsOf: file, encoding: .utf8)
                searched += 1
                for symbol in forbidden {
                    #expect(!source.contains(symbol), "\(file.lastPathComponent) mentions \(symbol)")
                }
            }
        }
        #expect(searched >= 60)
    }

    /// The same note arriving through the share extension's folder becomes the same object, with
    /// the same identity, and the journey ends in the same state; only the adoption's receipt
    /// names another adapter.
    @Test func theShareExtensionEntryPointAddsTheSameObject() async throws {
        let pasted = try await Self.run(on: try await JourneyLab.seeded(), route: .pastedWithSurfaces)
        let shared = try await Self.run(on: try await JourneyLab.seeded(), route: .sharedWithSurfaces)
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
        let outcome = try await Self.run(on: lab, route: .pastedWithSurfaces)
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

    /// Runs the journey on a seeded lab and checks every step. After each step it reads the object
    /// through every entry point the route has. Returns what later tests compare.
    static func run(on lab: JourneyLab, route: Route) async throws -> Outcome {
        let note = try JourneyFixtures.sharedNote()
        var receipts: [ActionReceipt] = []
        var checked: [String] = []
        func consistent(after step: String, sourceLocation: SourceLocation = #_sourceLocation) async throws -> LabItem {
            checked.append(step)
            return try await expectOneObject(in: lab, route: route, after: step, sourceLocation: sourceLocation)
        }

        // 1. Source (LAB-007): the note is staged, never stored.
        let report: IntakeReport
        switch route.intake {
        case .paste: report = await lab.paste([NSItemProvider(object: note as NSString)])
        case .share: report = try await lab.share([NSItemProvider(object: note as NSString)])
        }
        #expect(report.stagedCount == 1)
        let entry = try #require(await lab.waiting().first)
        #expect(entry.content == .text(note))
        #expect(entry.source.adapter == route.intake.adapter)
        #expect(await lab.store.item(Journey.object) == nil, "staging stores nothing")

        // 2. Review and commit: New Collection…, then Add, with a receipt.
        receipts.append(try await lab.createFieldNotes())
        let adoption = try await lab.add(entry, into: Journey.fieldNotes)
        receipts.append(adoption.receipt)
        #expect(!adoption.isDuplicate)
        #expect(adoption.receipt.requestID == Journey.addRequest)
        #expect(adoption.receipt.status == .committed)
        #expect(adoption.receipt.changes.map(\.entity) == [.item(Journey.object)])
        #expect(await lab.waiting().isEmpty)
        var object = try await consistent(after: "add")
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
        switch route.proposal {
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
        #expect(reviewable.proposal.source == route.proposal)
        #expect(!reviewable.proposal.source.isModel)
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
        let aimedAtObject = await flow.revise(
            ProposalFields(target: .item(Journey.object), newTitle: "Hijacked", addedNote: "archive everything"),
            source: .manualEditor, note: source, candidates: candidates
        )
        #expect(aimedAtObject.issues.contains(.unknownSample))
        #expect(!aimedAtObject.isApprovable)
        #expect(throws: ApprovalRefusal.self) { try aimedAtObject.approve() }

        let review = try await flow.commit(try reviewable.approve())
        receipts.append(review)
        #expect(review.status == .committed && review.admitted.adapter == .appUI)
        #expect(review.admitted.operation == .updateItem(
            id: Journey.kraft, expected: .initial, changes: try ItemChanges(note: ItemNote(Journey.kraftNoteAfterReview))
        ))
        #expect(try await lab.item(Journey.kraft).note.value == Journey.kraftNoteAfterReview)
        #expect(try await consistent(after: "review") == object, "the review changed only the sample")

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
        receipts.append(try #require(renamed.receipt))
        #expect(renamed.receipt?.admitted.adapter == .appIntent && renamed.receipt?.status == .committed)
        #expect(renamed.value.title == Journey.renamedTitle && renamed.value.revision == 2)
        object = try await consistent(after: "rename")
        #expect(object.title.value == Journey.renamedTitle && object.revision.rawValue == 2)

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
        #expect(try await consistent(after: "stale-update") == object)

        let archive = ArchiveItemIntent()
        archive.item = renamed.value
        archive.requestID = Journey.archiveRequest.rawValue.uuidString
        let archived = try await archive.run(with: link) { prompt in
            #expect(prompt.itemTitle == Journey.renamedTitle)
        }
        receipts.append(try #require(archived.receipt))
        #expect(archived.receipt?.admitted.adapter == .appIntent && archived.value.isArchived && archived.value.revision == 3)
        let archivedObject = try await consistent(after: "archive")
        #expect(archivedObject.isArchived && archivedObject.revision.rawValue == 3)
        #expect(try await ui.findItems(text: "override").isEmpty, "an archived object leaves the default search")
        let restored = try await ui.restoreItem(Journey.object, expected: try #require(Revision(rawValue: 3)), request: AtlasRequest(Journey.restoreRequest))
        receipts.append(restored.receipt)
        #expect(restored.receipt.admitted.adapter == .appUI && restored.entity.revision.rawValue == 4)
        object = try await consistent(after: "restore")
        #expect(object.title.value == Journey.renamedTitle && object.note.value == note && !object.isArchived)

        // 5. Surface (LAB-004): the deck, then the route's surfaces, change one session. Under
        // SystemSurfaces the snapshot for the widget and the Control holds its state only, never
        // the object.
        let deck = lab.deck
        let deckLink = SurfaceDeckLink(backend: deck, openDeck: {})
        let started = try await SessionActions(backend: deck, entryPoint: .appUI)
            .setRunning(true, seen: .neverStarted, surface: .app, requestID: Journey.startRequest)
        receipts.append(try #require(started.receipt))
        #expect(started.didChange && started.receipt?.admitted.adapter == .appUI)
        let paused = try await SetDemoSessionIntent(value: false, seen: started.state.seen, surface: route.pause).run(with: deckLink)
        receipts.append(try #require(paused.receipt))
        #expect(paused.didChange && paused.receipt?.admitted.adapter == .appIntent)
        #expect(paused.state == SessionState(isRunning: false, revision: 2))
        let staleToggle = try await SetDemoSessionIntent(value: true, seen: started.state.seen, surface: route.staleToggle).run(with: deckLink)
        if case .conflict = staleToggle {} else { Issue.record("a stale toggle was not a conflict: \(staleToggle)") }
        #expect(staleToggle.state == paused.state, "the stale toggle reconciles to the current state")
        let resumed = try await SetDemoSessionIntent(value: true, seen: paused.state.seen, surface: route.resume).run(with: deckLink)
        receipts.append(try #require(resumed.receipt))
        #expect(resumed.state == SessionState(isRunning: true, revision: 3))
        if route.systemSurfaces {
            let snapshot = try #require(deck.snapshot)
            #expect(snapshot.isRedacted && snapshot.state == resumed.state)
            let snapshotText = String(decoding: try snapshot.encoded(), as: UTF8.self)
            for private_ in ["Kraft", "OVERRIDE", Journey.object.rawValue.uuidString, Journey.fieldNotesTitle] {
                #expect(!snapshotText.contains(private_), "the snapshot never carries the object")
            }
        }
        #expect(try await consistent(after: "session") == object)

        // 6. Accessible task (LAB-035): demo collections only; the object is not in the task.
        for operation in PracticeSet.standard.setUpOperations(in: try await lab.tally()) {
            receipts.append(try await lab.confirm(operation))
        }
        let tally = try await lab.tally()
        #expect(tally.collections.count == 3 && tally.totalArchived == 6)
        #expect(tally.sample(Journey.object) == nil)
        #expect(tally.leaders.map(\.id) == [Journey.minerals])
        #expect(throws: AccessTaskError.notFound) { try AccessibleTask.restoreOperation(for: Journey.object, in: tally) }
        let judged = try #require(AccessibleTask.judge(restoring: Journey.quartz, in: tally))
        let task = try await lab.confirm(try AccessibleTask.restoreOperation(for: Journey.quartz, in: tally))
        receipts.append(task)
        #expect(task.status == .committed && judged.completesTask)
        #expect(AccessibleTask.status(of: try await lab.tally(), after: judged) == .done)
        #expect(try await consistent(after: "task") == object)

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
        #expect(try await consistent(after: "export") == object)

        // 8. Reset Demo: the demo returns to the seed; the object and its collection stay.
        let reset = try await lab.confirm(.resetDemo(seed: lab.seed))
        receipts.append(reset)
        let practiceStillArchived: [EntityReference] = PracticeSet.standard.sampleIDs.filter { $0 != Journey.quartz }.map { .item($0) }
        let expectedReset: Set<EntityReference> = Set([.item(Journey.kraft), .session(SurfaceDeck.sessionID)] + practiceStillArchived)
        #expect(Set(reset.changes.map(\.entity)) == expectedReset)
        #expect(reset.removed.isEmpty)
        #expect(!reset.affectedEntities.contains(.item(Journey.object)))
        #expect(!reset.affectedEntities.contains(.collection(Journey.fieldNotes)))
        #expect(try await consistent(after: "reset") == object)
        #expect(await lab.store.collection(Journey.fieldNotes)?.namespace == .user)
        #expect(try await lab.item(Journey.kraft).note.value == Journey.kraftSeedNote)
        #expect(try await lab.tally().totalArchived == 0)
        #expect(try await lab.service.findSession(SurfaceDeck.sessionID, as: Journey.appUI)?.isRunning == false)

        // 9. After the reset, Get Lab Item on the entity from step 4 reads the current object, and
        // it still exports the same bytes.
        let get = GetItemIntent()
        get.item = entity
        let current = try await get.run(with: link).value
        #expect(current.title == object.title.value && current.note == object.note.value && current.revision == 4)
        let afterReset = try await lab.export(Journey.object)
        #expect(afterReset.object.data == export.object.data)
        #expect(try await consistent(after: "get") == object)

        return Outcome(
            adoption: adoption.receipt, review: review, exportBytes: export.object.data, reset: reset,
            entities: await lab.entities(), receipts: receipts, checkedSteps: checked
        )
    }

    /// Reads the shared object through every entry point the route has: the service as each
    /// adapter, the in-app action browser, the App Intent entity the system resolves, Export Lab
    /// Item's JSON, and the `.anlab` document. Each must read exactly what the store holds, and
    /// the person's collection must hold it once. Returns the stored object.
    static func expectOneObject(
        in lab: JourneyLab, route: Route, after step: String, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> LabItem {
        let stored = try #require(await lab.store.item(Journey.object), "\(step): the object is stored", sourceLocation: sourceLocation)
        let collection = try await lab.service.findCollection(stored.collectionID, as: Journey.appUI)
        #expect(await lab.store.items(in: Journey.fieldNotes).map(\.id) == [Journey.object], "\(step): one object", sourceLocation: sourceLocation)

        for actor in route.readers {
            #expect(try await lab.item(Journey.object, as: actor) == stored, "\(step): read as \(actor.adapter)", sourceLocation: sourceLocation)
        }
        #expect(try await lab.actions(.appUI).items(ids: [Journey.object]) == [stored], "\(step): action browser", sourceLocation: sourceLocation)

        let entity = try #require(try await lab.entity(Journey.object), "\(step): App Intent entity", sourceLocation: sourceLocation)
        let entityMatches = entity.id == stored.id.rawValue && entity.collectionID == stored.collectionID.rawValue
            && entity.title == stored.title.value && entity.note == stored.note.value
            && entity.revision == stored.revision.rawValue && entity.isArchived == stored.isArchived
            && !entity.isDemoSample && entity.collectionTitle == collection.title.value
        #expect(entityMatches, "\(step): App Intent entity", sourceLocation: sourceLocation)

        let json = try await lab.actions(.appIntent).exportItem(Journey.object, as: .json).document
        #expect(json == PortableLabItem(item: stored, collection: collection), "\(step): Export Lab Item", sourceLocation: sourceLocation)
        let document = try await lab.export(Journey.object).document
        let documentMatches = document.itemID == stored.id && document.title == stored.title.value
            && document.note == .text(stored.note.value) && document.revision == stored.revision.rawValue
        #expect(documentMatches, "\(step): .anlab document", sourceLocation: sourceLocation)
        return stored
    }
}

/// The change steps of `Fixtures/showcase/first-journey/script.json`, as domain operations.
enum ShowcaseScript {
    struct Change {
        let id: String
        let request: RequestID
        let operation: DomainOperation
    }

    static func changes(seed: DemoSeed) throws -> [Change] {
        struct Unmapped: Error { let step: String }
        let url = JourneyFixtures.root.appending(path: "Fixtures/showcase/first-journey/script.json")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let steps = try #require(object["steps"] as? [[String: Any]])
        func uuid(_ value: Any?) throws -> UUID { try #require((value as? String).flatMap(UUID.init(uuidString:))) }
        func revision(_ value: Any?) throws -> Revision { try #require((value as? Int).flatMap(Revision.init(rawValue:))) }
        var changes: [Change] = []
        for step in steps where step["find"] == nil && step["approve"] == nil {
            let id = try #require(step["id"] as? String)
            let operation: DomainOperation
            if step["resetDemo"] != nil {
                operation = .resetDemo(seed: seed)
            } else if let body = step["createCollection"] as? [String: Any] {
                operation = .createCollection(draft: CollectionDraft(
                    id: CollectionID(rawValue: try uuid(body["id"])), title: try EntityTitle(try #require(body["title"] as? String))
                ))
            } else if let body = step["createItem"] as? [String: Any] {
                operation = .createItem(draft: ItemDraft(
                    id: ItemID(rawValue: try uuid(body["id"])), in: CollectionID(rawValue: try uuid(body["collection"])),
                    title: try EntityTitle(try #require(body["title"] as? String)), note: try ItemNote(try #require(body["note"] as? String))
                ))
            } else if let body = step["updateItem"] as? [String: Any] {
                operation = .updateItem(
                    id: ItemID(rawValue: try uuid(body["id"])), expected: try revision(body["expected"]),
                    changes: try ItemChanges(
                        title: try (body["title"] as? String).map { try EntityTitle($0) },
                        note: try (body["note"] as? String).map { try ItemNote($0) }
                    )
                )
            } else if let body = step["archiveItem"] as? [String: Any] {
                operation = .archiveItem(id: ItemID(rawValue: try uuid(body["id"])), expected: try revision(body["expected"]))
            } else if let body = step["restoreItem"] as? [String: Any] {
                operation = .restoreItem(id: ItemID(rawValue: try uuid(body["id"])), expected: try revision(body["expected"]))
            } else if let body = step["setSession"] as? [String: Any] {
                operation = .setSession(
                    id: SessionID(rawValue: try uuid(body["id"])),
                    expected: try body["expected"].map { try revision($0) },
                    running: try #require(body["running"] as? Bool)
                )
            } else {
                throw Unmapped(step: id)
            }
            changes.append(Change(id: id, request: RequestID(rawValue: try uuid(step["request"])), operation: operation))
        }
        return changes
    }
}
