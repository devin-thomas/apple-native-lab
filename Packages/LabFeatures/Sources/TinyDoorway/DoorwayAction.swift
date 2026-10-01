import Foundation
import LabDomain

/// Builds the one domain operation a confirmed visit may commit, and the reset that removes only
/// this experiment's visit markers.
///
/// Entering the experiment or holding a `SignedLinkProposal` never grants permission. Only a
/// separate confirm action may call `visitOperation`, and the host commits it through
/// `OperationService` with a receipt (and a grant when the policy requires one).
public enum DoorwayAction {
    /// Appends the visit marker to a demo sample's note at the revision the person saw.
    public static func visitOperation(
        for proposal: SignedLinkProposal,
        item: LabItem
    ) throws(DoorwayError) -> DomainOperation {
        guard item.id == proposal.itemID else {
            throw .itemUnavailable(item.title.value)
        }
        guard item.namespace == .demo else {
            throw .itemUnavailable(item.title.value)
        }
        guard !item.isArchived else {
            throw .itemUnavailable(item.title.value)
        }
        if item.note.value.contains(DoorwayPolicy.visitMarker) {
            throw .alreadyVisited(item.title.value)
        }
        let combined: String
        if item.note.value.isEmpty {
            combined = DoorwayPolicy.visitMarker
        } else {
            combined = item.note.value + "\n" + DoorwayPolicy.visitMarker
        }
        guard let note = try? ItemNote(combined) else {
            throw .itemUnavailable(item.title.value)
        }
        guard let changes = try? ItemChanges(note: note) else {
            throw .itemUnavailable(item.title.value)
        }
        return .updateItem(id: item.id, expected: item.revision, changes: changes)
    }

    /// Strips the visit marker from demo samples that still carry it. Each is one `updateItem`.
    public static func resetVisitOperations(in items: [LabItem]) -> [DomainOperation] {
        items.compactMap { item -> DomainOperation? in
            guard item.namespace == .demo, !item.isArchived else { return nil }
            guard item.note.value.contains(DoorwayPolicy.visitMarker) else { return nil }
            let stripped = item.note.value
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { $0 != DoorwayPolicy.visitMarker }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let note = try? ItemNote(stripped), let changes = try? ItemChanges(note: note) else {
                return nil
            }
            return .updateItem(id: item.id, expected: item.revision, changes: changes)
        }
    }
}
