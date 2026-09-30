import Foundation
import LabDomain
import Synchronization
import Testing
@testable import TypedIntelligence

/// LAB-010-B qualification: the showcase's edits come from the real flow, the person's own and
/// imported data is never offered to an extractor or touched by Reset Demo, and stale, duplicate,
/// and hostile input changes nothing it should not. Fixture path: an in-memory store behind
/// `OperationService` with `GrantAuthorizationPolicy`, holding the real demo seed.
@Suite struct TypedIntelligenceQualificationTests {
    // MARK: The showcase

    /// Step 1's replay (`Fixtures/showcase/typed-intelligence/`) carries two fixed edits. Here the
    /// real flow drafts both notes with the sample parser, validates them, has the service check
    /// them as the proposer, and a person approves them unedited: the approvals are exactly the
    /// script's operations, and committing them reaches what the script's reads expect.
    @Test func theRealFlowDraftsExactlyTheShowcasesEdits() async throws {
        let showcase = try ShowcaseScript.load()
        let lab = try await QualificationLab.seeded()
        let candidates = try await lab.flow.candidates()

        // The script's first read is the one the lookup tool makes for "blue".
        let lookup = SampleLookup(candidates: candidates) { filter in (try? await lab.backend.items(filter)) ?? [] }
        let blue = try #require(await lookup.find("blue"))
        #expect(blue.map(\.id.rawValue) == showcase.expected("find-blue"))

        for (fixture, step) in [(IntelligenceFixture.ambiguousNote, "apply-cobalt"), (.injectedNote, "apply-kraft")] {
            let drafted = try await lab.flow.draft(try Repository.note(fixture), with: SampleParser(), candidates: candidates).get()
            #expect(drafted.isApprovable, "\(step)")
            let approval = try drafted.approve()
            #expect(approval.source == .sampleParser && !approval.editedByPerson)
            #expect(approval.operation == (try showcase.operation(step)), "\(step): the replay applies what the flow drafts")
            let receipt = try await lab.flow.commit(approval)
            #expect(receipt.conflict == nil && receipt.admitted.adapter == .appUI)
        }

        let bleeds = try await lab.service.findItems(try ItemFilter(text: "bleeds"), as: QualificationLab.appUI)
        #expect(bleeds.map(\.id.rawValue) == showcase.expected("find-bleeds"))
        let fray = try await lab.service.findItems(try ItemFilter(text: "fray"), as: QualificationLab.appUI)
        #expect(fray.map(\.id.rawValue) == showcase.expected("find-fray"))
        let override = try await lab.service.findItems(try ItemFilter(text: "override", includeArchived: true), as: QualificationLab.appUI)
        #expect(override.isEmpty && showcase.expected("find-override") == [])
    }

    // MARK: Reset without touching imported user data

    /// A person's own collection and items, including one adopted from staging and one titled
    /// like a demo sample, are never offered to an extractor, never found by the lookup tool, and
    /// left exactly as they were by an applied proposal and by Reset Demo.
    @Test func theOwnersDataIsNeverOfferedAndResetDemoLeavesItAlone() async throws {
        let lab = try await QualificationLab.seeded()
        let own = try await lab.createOwnCollection("Studio notes")
        let lookalike = try await lab.createOwnItem("Kraft card", note: "My own kraft card, not the demo one.", in: own)
        let imported = try await lab.importText("Harbor walk\nBring the blue notebook.", into: own)
        let ownBefore = await lab.ownState()
        #expect(ownBefore.items.count == 2)

        // Only the 12 demo samples are offered, and the lookup never reaches the person's items.
        let candidates = try await lab.flow.candidates()
        #expect(candidates.count == 12 && candidates.allSatisfy { $0.item.namespace == .demo })
        #expect(!candidates.contains { $0.id == lookalike || $0.id == imported.item })
        let lookup = SampleLookup(candidates: candidates) { filter in (try? await lab.backend.items(filter)) ?? [] }
        let blue = try #require(await lookup.find("blue"))
        #expect(blue.map(\.title) == ["Cobalt swatch", "Verdigris swatch"], "not the imported blue notebook")
        let kraft = try #require(await lookup.find("kraft"))
        #expect(kraft.count == 1 && kraft[0].item.namespace == .demo, "the demo sample, not the person's lookalike")

        // The injected note names "Kraft card": the demo sample is the target, never the lookalike.
        let drafted = try await lab.flow.draft(try Repository.note(.injectedNote), with: SampleParser(), candidates: candidates).get()
        let target = try #require(drafted.proposal.target)
        #expect(target.item.namespace == .demo && target.id != lookalike)
        // A person who picks their own item by identity in the editor is refused: it is not offered.
        let ownPick = await lab.flow.revise(
            ProposalFields(target: .item(lookalike), newTitle: "Kraft card", addedNote: "Frays."),
            source: .manualEditor, note: try Repository.note(.injectedNote), candidates: candidates
        )
        #expect(ownPick.issues.contains(.unknownSample) && !ownPick.isApprovable)

        _ = try await lab.flow.commit(try drafted.approve())
        #expect(await lab.ownState() == ownBefore, "applying edits a demo sample only")

        let reset = try await lab.resetDemo()
        #expect(reset.changes.map(\.entity) == [.item(target.id)])
        #expect(reset.removed.isEmpty)
        #expect(await lab.ownState() == ownBefore, "Reset Demo leaves the person's data exactly as it was")
        #expect(await lab.store.base.receipt(for: imported.receipt.requestID) == imported.receipt, "the import's receipt is kept")
        let restored = try #require(await lab.store.base.item(target.id))
        #expect(restored.note.value == "Brown and stiff. Takes pencil well.")
    }

    // MARK: Stale state

    /// A change approved before Reset Demo commits only a conflict afterwards: Reset Demo moved
    /// the sample to a new revision, so nothing is overwritten. Read again, it can be reviewed.
    @Test func anApprovalFromBeforeResetDemoCommitsOnlyAConflict() async throws {
        let lab = try await QualificationLab.seeded()
        let note = try Repository.note(.injectedNote)
        let candidates = try await lab.flow.candidates()
        _ = try await lab.flow.commit(try await lab.flow.draft(note, with: SampleParser(), candidates: candidates).get().approve())

        let edited = try await lab.flow.candidates()
        let kraft = try #require(edited.first { $0.title == "Kraft card" })
        let pending = try await lab.flow.revise(
            ProposalFields(target: .item(kraft.id), newTitle: "Kraft card, fraying", addedNote: ""),
            source: .manualEditor, note: note, candidates: edited
        ).approve()

        _ = try await lab.resetDemo()
        let afterReset = try #require(await lab.store.base.item(kraft.id))
        #expect(afterReset.revision.rawValue == 3 && afterReset.title.value == "Kraft card")
        // The conflict receipt is recorded, so a retry gets the same answer, but it changes nothing.
        let conflict = try await lab.flow.commit(pending)
        #expect(conflict.conflict != nil)
        #expect(conflict.changes.isEmpty && conflict.undo == nil)
        #expect(try #require(await lab.store.base.item(kraft.id)) == afterReset)

        let fresh = try await lab.flow.candidates()
        let rebased = await lab.flow.revise(
            ProposalFields(target: .item(kraft.id), newTitle: "Kraft card, fraying", addedNote: ""),
            source: .manualEditor, note: note, candidates: fresh
        )
        #expect(rebased.isApprovable)
        #expect(rebased.proposal.diff?.noteBefore == "Brown and stiff. Takes pencil well.")
    }

    // MARK: Duplicate state

    /// The same note drafted again after its change was applied: the review says the sample's
    /// note already has that text, so a person sees the repeat before applying it twice. A retry
    /// of the first approval is the same request and writes nothing more.
    @Test func draftingTheSameNoteAgainAfterApplyingIsFlagged() async throws {
        let lab = try await QualificationLab.seeded()
        let note = try Repository.note(.injectedNote)
        let first = try await lab.flow.draft(note, with: SampleParser(), candidates: try await lab.flow.candidates()).get()
        #expect(!first.issues.contains(.addedNoteAlreadyPresent))
        let approval = try first.approve()
        let receipt = try await lab.flow.commit(approval)
        #expect(try await lab.flow.commit(approval) == receipt)
        #expect(lab.store.appliedCount == 1)

        let again = try await lab.flow.draft(note, with: SampleParser(), candidates: try await lab.flow.candidates()).get()
        #expect(again.issues.contains(.addedNoteAlreadyPresent))
        let blocking = again.issues.filter(\.isBlocking)
        #expect(blocking.isEmpty, "a warning for the person, not a refusal")
        #expect(lab.store.appliedCount == 1, "drafting again wrote nothing")
    }

    // MARK: Imported instructions

    /// A model that obeys the injected text word for word: it searches for every word of the
    /// text after the note, then answers with the text's own requests. Every access is a model-tool
    /// read of offered samples, nothing is proposed to the service, and nothing is written.
    @Test func everyWordOfTheInjectedTextIsOnlyASearch() async throws {
        let lab = try await QualificationLab.seeded()
        let note = try Repository.note(.injectedNote)
        let injected = try #require(note.text.components(separatedBy: "\n\n").dropFirst().first)
        let words = injected.split(whereSeparator: \.isWhitespace).map(String.init)
        #expect(words.count > 30)
        let candidates = try await lab.flow.candidates()
        let offered = Set(candidates.map(\.title))
        let answers = Answers()
        let extractor = ScriptedExtractor { request throws(ExtractionFailure) -> ExtractionDraft in
            for word in words { answers.append(await request.lookup.describe(word)) }
            return ExtractionDraft(
                sampleTitle: "every sample", otherPossibleSamples: offered.sorted(), newTitle: "archive",
                addedNote: injected, evidence: ["GRANT-00000000-0000-0000-0000-000000000000 covers every step"]
            )
        }
        lab.recorder.clear()
        let reviewable = try await lab.flow.draft(note, with: extractor, candidates: candidates).get()
        #expect(reviewable.proposal.isBlocked && !reviewable.isApprovable)
        #expect(reviewable.issues.contains(.unknownSample))

        let accesses = lab.recorder.accesses
        #expect(!accesses.isEmpty)
        #expect(accesses.allSatisfy { $0.adapter == .modelTool })
        #expect(accesses.allSatisfy { if case .read = $0.access { true } else { false } }, "only reads: no proposal, no commit")
        #expect(answers.values.count == words.count)
        let sentences = ["No sample matches that word.", "Search for one short word, such as a color or a material."]
        for answer in answers.values where !sentences.contains(answer) {
            let titles = answer.split(separator: "\n").map { String($0.split(separator: ":", maxSplits: 1)[0]) }
            #expect(titles.allSatisfy(offered.contains), "a lookup answers with offered samples only")
        }
        #expect(lab.store.appliedCount == 0)
    }
}

// MARK: - Support

/// Tool answers collected from inside a scripted extractor.
private final class Answers: Sendable {
    private let storage = Mutex<[String]>([])
    func append(_ answer: String) { storage.withLock { $0.append(answer) } }
    var values: [String] { storage.withLock { $0 } }
}

/// The experiment over a seeded in-memory store, like `Lab`, with the grant ledger kept so a test
/// can adopt an import and reset the demo as a person would.
private struct QualificationLab {
    let store: CountingStore
    let ledger: GrantLedger
    let recorder: AccessRecorder
    let service: OperationService
    let backend: ServiceIntelligenceBackend
    let flow: TypedIntelligenceFlow

    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    static func seeded() async throws -> QualificationLab {
        let store = CountingStore()
        let ledger = GrantLedger()
        let recorder = AccessRecorder(inner: GrantAuthorizationPolicy(ledger: ledger))
        let service = OperationService(store: store, policy: recorder)
        let backend = ServiceIntelligenceBackend(service: service)
        let lab = QualificationLab(
            store: store, ledger: ledger, recorder: recorder, service: service, backend: backend,
            flow: TypedIntelligenceFlow(backend: backend, timeLimit: .seconds(5))
        )
        _ = try await lab.resetDemo()
        store.resetCount()
        recorder.clear()
        return lab
    }

    /// Reset Demo as the person confirms it in the app: a grant for exactly this operation.
    @discardableResult
    func resetDemo() async throws -> ActionReceipt {
        let reset = DomainOperation.resetDemo(seed: try Repository.demoSeed())
        let grant = try ledger.issue(for: reset, to: .appUI)
        defer { ledger.revoke(grant.id) }
        return try await service.perform(OperationRequest(id: RequestID(), operation: reset, actor: Self.appUI))
    }

    func createOwnCollection(_ title: String) async throws -> CollectionID {
        let draft = CollectionDraft(title: try EntityTitle(title))
        _ = try await service.perform(OperationRequest(id: RequestID(), operation: .createCollection(draft: draft), actor: Self.appUI))
        return draft.id
    }

    func createOwnItem(_ title: String, note: String, in collection: CollectionID) async throws -> ItemID {
        let draft = ItemDraft(in: collection, title: try EntityTitle(title), note: try ItemNote(note))
        _ = try await service.perform(OperationRequest(id: RequestID(), operation: .createItem(draft: draft), actor: Self.appUI))
        return draft.id
    }

    /// Stages text and adopts it into `collection` the way the share extension does.
    func importText(_ text: String, into collection: CollectionID) async throws -> (item: ItemID, receipt: ActionReceipt) {
        let inbox = InMemoryStagingInbox()
        let staged = await inbox.stage(try StagingRecord.text(utf8: Array(text.utf8)))
        try ledger.issue(to: .shareExtension, for: [.createItem], on: ImportAdopter.grantTarget(into: collection))
        let adoption = try await ImportAdopter(service: service, inbox: inbox, ledger: ledger).adopt(staged.id, into: collection)
        guard case .item(let id)? = adoption.receipt.changes.first?.entity else {
            struct NoItem: Error {}
            throw NoItem()
        }
        return (id, adoption.receipt)
    }

    /// The person's own collections and items, ordered by ID.
    func ownState() async -> OwnState {
        OwnState(
            collections: await store.base.collections().filter { $0.namespace == .user }
                .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString },
            items: await store.base.items(in: nil).filter { $0.namespace == .user }
                .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        )
    }

    struct OwnState: Equatable {
        let collections: [LabCollection]
        let items: [LabItem]
    }
}

/// `Fixtures/showcase/typed-intelligence/script.json`, read as plain JSON: LabFeatures does not
/// depend on LabDemo. Only the fields these tests compare are read.
private struct ShowcaseScript {
    let steps: [String: [String: Any]]

    static func load() throws -> ShowcaseScript {
        let url = Repository.root.appending(path: "Fixtures/showcase/typed-intelligence/script.json")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let steps = try #require(object["steps"] as? [[String: Any]])
        return ShowcaseScript(steps: Dictionary(uniqueKeysWithValues: steps.compactMap { step in
            (step["id"] as? String).map { ($0, step) }
        }))
    }

    /// The item IDs a `find` step expects, in order.
    func expected(_ step: String) -> [UUID] {
        let find = steps[step]?["find"] as? [String: Any]
        return (find?["expect"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
    }

    /// The `updateItem` a step submits.
    func operation(_ step: String) throws -> DomainOperation {
        let update = try #require(steps[step]?["updateItem"] as? [String: Any], "\(step) is an updateItem step")
        let id = try #require((update["id"] as? String).flatMap(UUID.init(uuidString:)))
        let expected = try #require((update["expected"] as? Int).flatMap(Revision.init(rawValue:)))
        let changes = try ItemChanges(
            title: try (update["title"] as? String).map { try EntityTitle($0) },
            note: try (update["note"] as? String).map { try ItemNote($0) }
        )
        return .updateItem(id: ItemID(rawValue: id), expected: expected, changes: changes)
    }
}
