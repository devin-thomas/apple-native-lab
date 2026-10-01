import Foundation
import LabDomain
import Testing
@testable import TinyDoorway

@Suite struct ActionTests {
    @Test func confirmingAVisitCommitsThroughTheOperationService() async throws {
        let lab = try await TestLab.seeded()
        let context = InvocationContext(source: .fixtureReplay, rawURL: DemoLinks.visitHTTPS)
        guard case .proposal(let proposal) = DoorwayValidator.validate(context) else {
            Issue.record("fixture must validate")
            return
        }
        let before = try await lab.item(proposal.itemID)
        let operation = try DoorwayAction.visitOperation(for: proposal, item: before)
        #expect(operation.kind == .updateItem)

        let receipt = try await lab.perform(operation)
        #expect(receipt.conflict == nil)
        #expect(receipt.admitted.adapter == .appUI)
        #expect(receipt.undo?.kind == .updateItem)

        let after = try await lab.item(proposal.itemID)
        #expect(after.note.value.contains(DoorwayPolicy.visitMarker))
        #expect(after.revision == before.revision.next())
    }

    @Test func aProposalNeverBecomesAGrantOrRunsWithoutConfirm() async throws {
        let lab = try await TestLab.seeded()
        let context = InvocationContext(source: .fixtureReplay, rawURL: DemoLinks.visitHTTPS)
        guard case .proposal(let proposal) = DoorwayValidator.validate(context) else {
            Issue.record("fixture must validate")
            return
        }
        // Holding the proposal alone leaves the store unchanged.
        let before = try await lab.item(proposal.itemID)
        #expect(!before.note.value.contains(DoorwayPolicy.visitMarker))
        #expect(proposal.seal.hex.count == 64)
    }

    @Test func alreadyVisitedIsRefusedWithoutASecondWrite() async throws {
        let lab = try await TestLab.seeded()
        guard case .proposal(let proposal) = DoorwayValidator.validate(
            InvocationContext(source: .fixtureReplay, rawURL: DemoLinks.visitDeepLink)
        ) else {
            Issue.record("fixture must validate")
            return
        }
        let first = try DoorwayAction.visitOperation(for: proposal, item: try await lab.item(proposal.itemID))
        _ = try await lab.perform(first)
        let visited = try await lab.item(proposal.itemID)
        #expect(throws: DoorwayError.alreadyVisited(DoorwayPolicy.sampleItemTitle)) {
            try DoorwayAction.visitOperation(for: proposal, item: visited)
        }
    }

    @Test func userDataCannotBeTheVisitTarget() async throws {
        let lab = try await TestLab.seeded()
        let mine = CollectionDraft(title: try EntityTitle("Field notes"))
        _ = try await lab.perform(.createCollection(draft: mine))
        let draft = ItemDraft(in: mine.id, title: try EntityTitle("Graphite stick"))
        _ = try await lab.perform(.createItem(draft: draft))
        let userItem = try await lab.item(draft.id)

        // Forge a proposal-shaped value by validating a demo link, then swap the store item.
        guard case .proposal(let proposal) = DoorwayValidator.validate(
            InvocationContext(source: .fixtureReplay, rawURL: DemoLinks.visitHTTPS)
        ) else {
            Issue.record("fixture must validate")
            return
        }
        #expect(throws: DoorwayError.self) {
            try DoorwayAction.visitOperation(for: proposal, item: userItem)
        }
        #expect(userItem.note.value.contains(DoorwayPolicy.visitMarker) == false)
    }

    @Test func resetVisitsRemovesOnlyTheMarker() async throws {
        let lab = try await TestLab.seeded()
        guard case .proposal(let proposal) = DoorwayValidator.validate(
            InvocationContext(source: .fixtureReplay, rawURL: DemoLinks.visitHTTPS)
        ) else {
            Issue.record("fixture must validate")
            return
        }
        _ = try await lab.perform(try DoorwayAction.visitOperation(for: proposal, item: try await lab.item(proposal.itemID)))
        let operations = DoorwayAction.resetVisitOperations(in: try await lab.demoItems())
        #expect(operations.count == 1)
        for operation in operations {
            _ = try await lab.perform(operation)
        }
        let after = try await lab.item(proposal.itemID)
        #expect(!after.note.value.contains(DoorwayPolicy.visitMarker))
        #expect(after.note.value.contains("Clear and six-sided"))
    }

    @Test func aDuplicateRequestCommitsOnce() async throws {
        let lab = try await TestLab.seeded()
        guard case .proposal(let proposal) = DoorwayValidator.validate(
            InvocationContext(source: .fixtureReplay, rawURL: DemoLinks.visitHTTPS)
        ) else {
            Issue.record("fixture must validate")
            return
        }
        let operation = try DoorwayAction.visitOperation(for: proposal, item: try await lab.item(proposal.itemID))
        let request = RequestID()
        let first = try await lab.perform(operation, requestID: request)
        let second = try await lab.perform(operation, requestID: request)
        #expect(first.id == second.id)
        #expect(try await lab.item(proposal.itemID).note.value.components(separatedBy: DoorwayPolicy.visitMarker).count == 2)
    }

    @Test func aStaleVisitChangesNothing() async throws {
        let lab = try await TestLab.seeded()
        guard case .proposal(let proposal) = DoorwayValidator.validate(
            InvocationContext(source: .fixtureReplay, rawURL: DemoLinks.visitHTTPS)
        ) else {
            Issue.record("fixture must validate")
            return
        }
        let stale = try await lab.item(proposal.itemID)
        let operation = try DoorwayAction.visitOperation(for: proposal, item: stale)
        // Another edit moves the revision forward.
        _ = try await lab.perform(.updateItem(
            id: stale.id,
            expected: stale.revision,
            changes: try ItemChanges(note: try ItemNote(stale.note.value + "\nEdited elsewhere."))
        ))
        let receipt = try await lab.perform(operation)
        #expect(receipt.conflict != nil)
        #expect(receipt.changes.isEmpty)
        #expect(!((try await lab.item(proposal.itemID)).note.value.contains(DoorwayPolicy.visitMarker)))
    }

    @Test func cancellationStopsBetweenResetCommits() async throws {
        let lab = try await TestLab.seeded()
        // Visit two samples so reset has two operations.
        for url in [
            DemoLinks.visitHTTPS,
            "nativelab://doorway/open/visit?item=9b97bf2f-4d0b-4197-9ca8-36489df40455",
        ] {
            guard case .proposal(let proposal) = DoorwayValidator.validate(
                InvocationContext(source: .fixtureReplay, rawURL: url)
            ) else {
                Issue.record("link must validate: \(url)")
                return
            }
            _ = try await lab.perform(try DoorwayAction.visitOperation(for: proposal, item: try await lab.item(proposal.itemID)))
        }
        let operations = DoorwayAction.resetVisitOperations(in: try await lab.demoItems())
        #expect(operations.count == 2)
        var done = 0
        for operation in operations {
            if done == 1 { break } // stop as a cancelled run would
            _ = try await lab.perform(operation)
            done += 1
        }
        let remaining = DoorwayAction.resetVisitOperations(in: try await lab.demoItems())
        #expect(remaining.count == 1)
    }
}
