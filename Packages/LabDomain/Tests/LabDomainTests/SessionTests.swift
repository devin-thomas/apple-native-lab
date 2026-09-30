import Foundation
import LabDomain
import Testing

/// LAB-004 Surface Deck: one small, reversible session state that changes only through
/// `OperationService`, with a receipt and an undo, under the same adapter ceilings and grants as
/// every other operation (ADR-011, ADR-013).
@Suite struct SessionTests {
    static let id = SessionID(rawValue: uuid(700))

    private func set(_ running: Bool, expected: Revision?) -> DomainOperation {
        .setSession(id: Self.id, expected: expected, running: running)
    }

    @Test func startingANeverStartedSessionCreatesItWithAReceiptAndAnUndo() async throws {
        let lab = Harness()
        #expect(try await lab.service.findSession(Self.id, as: .appUI) == nil)

        let receipt = try await lab.perform(set(true, expected: nil))
        #expect(receipt.status == .committed)
        #expect(receipt.changes.map(\.entity) == [.session(Self.id)])
        #expect(receipt.changes.map(\.previousRevision) == [nil])
        #expect(receipt.changes.map(\.newRevision) == [.initial])
        #expect(receipt.summary == "Started the demo session.")
        #expect(receipt.undo == set(false, expected: .initial))
        #expect(try await lab.service.findSession(Self.id, as: .appUI) == LabSession(id: Self.id, isRunning: true))
    }

    @Test func theUndoReversesTheChangeAndOffersTheOppositeUndo() async throws {
        let lab = Harness()
        let started = try await lab.perform(set(true, expected: nil))
        let undone = try await lab.perform(try #require(started.undo))
        #expect(undone.summary == "Paused the demo session.")
        #expect(undone.changes.map(\.newRevision) == [.r(2)])
        #expect(undone.undo == set(true, expected: .r(2)))
        #expect(try await lab.service.findSession(Self.id, as: .appUI)?.isRunning == false)

        let redone = try await lab.perform(try #require(undone.undo))
        #expect(redone.summary == "Started the demo session.")
        #expect(try await lab.service.findSession(Self.id, as: .appUI) == LabSession(id: Self.id, isRunning: true, revision: .r(3)))
    }

    @Test func aStaleToggleGetsAConflictReceiptAndChangesNothing() async throws {
        let lab = Harness()
        _ = try await lab.perform(set(true, expected: nil))
        _ = try await lab.perform(set(false, expected: .initial))
        let commitsBefore = await lab.store.appliedCommits

        // A surface still showing revision 1 (running) asks to pause.
        let requestID = RequestID()
        let stale = try await lab.perform(set(false, expected: .initial), id: requestID)
        let conflict = try #require(stale.conflict)
        #expect(conflict.entity == .session(Self.id) && conflict.expected == .initial && conflict.current == .r(2))
        #expect(stale.changes.isEmpty && stale.undo == nil)
        #expect(stale.summary == "Not applied because the demo session changed: expected revision 1, found 2.")
        #expect(try await lab.service.findSession(Self.id, as: .appUI) == LabSession(id: Self.id, isRunning: false, revision: .r(2)))

        // The conflict is recorded: a retry of that request gets the same answer.
        #expect(try await lab.perform(set(false, expected: .initial), id: requestID) == stale)
        #expect(await lab.store.appliedCommits == commitsBefore + 1)
    }

    @Test func requestsThatWouldChangeNothingOrNameAMissingSessionAreRefused() async throws {
        let lab = Harness()
        await #expect(throws: OperationError.ruleViolation(.noChanges(.session(Self.id)))) {
            try await lab.perform(set(false, expected: nil))
        }
        await #expect(throws: OperationError.notFound(.session(Self.id))) {
            try await lab.perform(set(true, expected: .r(3)))
        }
        _ = try await lab.perform(set(true, expected: nil))
        await #expect(throws: OperationError.ruleViolation(.noChanges(.session(Self.id)))) {
            try await lab.perform(set(true, expected: .initial))
        }
        // A surface that saw no session while one exists is out of date.
        await #expect(throws: OperationError.ruleViolation(.alreadyExists(.session(Self.id)))) {
            try await lab.perform(set(false, expected: nil))
        }
        #expect(await lab.store.appliedCommits == 1)
    }

    @Test func settingASessionIsNotDestructiveAndNeedsNoGrantFromTheAppOrAnIntent() async throws {
        #expect(!OperationKind.setSession.isDestructive)
        #expect(OperationKind.setSession.commitPermission == .commit)
        let lab = GrantedLab()
        let started = try await lab.service.perform(OperationRequest(id: RequestID(), operation: set(true, expected: nil), actor: .appIntent))
        #expect(started.admitted.adapter == .appIntent)
        let paused = try await lab.service.perform(OperationRequest(id: RequestID(), operation: set(false, expected: .initial), actor: .appUI))
        #expect(paused.admitted.adapter == .appUI)
        #expect(lab.ledger.liveGrants.isEmpty)
    }

    @Test func aModelToolMayReadAndProposeButNeverCommitASessionChange() async throws {
        let lab = Harness()
        #expect(try await lab.service.findSession(Self.id, as: .modelTool) == nil)
        let proposal = try await lab.service.propose(set(true, expected: nil), as: .modelTool)
        #expect(proposal.summary == "Start the demo session.")
        let error = await #expect(throws: OperationError.self) {
            try await lab.perform(set(true, expected: nil), as: .modelTool)
        }
        #expect(error?.denial?.reason == .outsideAdapterCeiling)
        #expect(await lab.store.appliedCommits == 0)
    }

    @Test func contentFromOutsideTheAppCannotToggleTheSessionWithoutAGrant() async throws {
        let lab = GrantedLab()
        let error = await #expect(throws: OperationError.self) {
            try await lab.service.perform(OperationRequest(
                id: RequestID(), operation: set(true, expected: nil), actor: ActorScope.granted(.shareExtension)
            ))
        }
        #expect(error?.denial?.reason == .deniedByPolicy)
        #expect(try await lab.service.findSession(Self.id, as: .appUI) == nil)

        // A grant, when one is issued, covers exactly this session.
        let grant = try lab.ledger.issue(for: set(true, expected: nil), to: .shareExtension)
        #expect(grant.target == .entity(.session(Self.id)))
    }

    @Test func resetDemoPausesARunningSessionAtItsNextRevision() async throws {
        let lab = Harness()
        let seed = try DemoSeed(version: 1, collections: [CollectionDraft(id: CollectionID(rawValue: uuid(701)), title: "Samples")], items: [])
        _ = try await lab.perform(.resetDemo(seed: seed))
        _ = try await lab.perform(set(true, expected: nil))
        let reset = try await lab.perform(.resetDemo(seed: seed))
        #expect(reset.changes.map(\.entity) == [.session(Self.id)])
        #expect(reset.changes.map(\.previousRevision) == [.initial])
        #expect(reset.changes.map(\.newRevision) == [.r(2)])
        #expect(reset.removed.isEmpty)
        #expect(reset.summary == "Reset the demo to its original 1 collection and 0 items: paused 1 session.")
        #expect(try await lab.service.findSession(Self.id, as: .appUI) == LabSession(id: Self.id, isRunning: false, revision: .r(2)))

        // A toggle prepared before the reset now conflicts instead of applying.
        let stale = try await lab.perform(set(false, expected: .initial))
        #expect(stale.conflict != nil)
    }

    @Test func aSessionReceiptRoundTripsThroughJSON() async throws {
        let lab = Harness()
        let receipt = try await lab.perform(set(true, expected: nil))
        let data = try JSONEncoder().encode(receipt)
        #expect(try JSONDecoder().decode(ActionReceipt.self, from: data) == receipt)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""kind":"session""#))
        #expect(set(false, expected: .initial).rebased(onto: .r(5)) == set(false, expected: .r(5)))
    }
}
