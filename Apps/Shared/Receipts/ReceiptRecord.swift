import Foundation
import LabDomain

/// A receipt the host received this session, with the titles it knew for the entities involved.
///
/// The receipt itself is the service's immutable record; the titles are display help only, taken
/// from demo snapshots before and after the change, so a removed sample still has a name.
struct ReceiptRecord: Identifiable, Hashable, Sendable {
    let receipt: ActionReceipt
    let recordedAt: Date
    let names: [EntityReference: String]

    var id: OperationID { receipt.operationID }
}

/// Everything the receipt inspector shows, as plain values, so it can be checked without a view.
struct ReceiptPresentation: Hashable {
    struct EntityLine: Identifiable, Hashable {
        let reference: EntityReference
        let kind: String
        let name: String?
        let revision: String

        var id: EntityReference { reference }

        /// One sentence for VoiceOver: kind, name, then what happened to it.
        var spokenDescription: String {
            [kind, name.map { "“\($0)”" }, revision].compactMap(\.self).joined(separator: ", ")
        }
    }

    struct UndoOffer: Hashable {
        /// What the undo does, for example "Restore Item “Amber swatch”".
        let title: String
        /// The revision the undo expects the entity to have.
        let expectedRevision: String
    }

    let operation: String
    let adapter: String
    let operationID: String
    let requestID: String
    let isCommitted: Bool
    let status: String
    let summary: String
    let changes: [EntityLine]
    let removals: [EntityLine]
    let undo: UndoOffer?
    /// Why there is no undo offer, when there is none.
    let noUndoReason: String?

    init(_ record: ReceiptRecord) {
        let receipt = record.receipt
        let kind = receipt.admitted.operation.kind
        func name(_ reference: EntityReference) -> String? { record.names[reference] }

        operation = receipt.admitted.operation.title
        adapter = receipt.admitted.adapter.title
        operationID = receipt.operationID.description
        requestID = receipt.requestID.description
        summary = receipt.summary
        if let conflict = receipt.conflict {
            isCommitted = false
            status = "Not applied: expected revision \(conflict.expected), found \(conflict.current)"
        } else {
            isCommitted = true
            status = "Committed"
        }
        changes = receipt.changes.map { change in
            EntityLine(
                reference: change.entity,
                kind: change.entity.kind.title,
                name: name(change.entity),
                revision: change.previousRevision.map { "Revision \($0) → \(change.newRevision)" }
                    ?? "Created at revision \(change.newRevision)"
            )
        }
        removals = receipt.removed.map { reference in
            EntityLine(reference: reference, kind: reference.kind.title, name: name(reference), revision: "Removed")
        }
        if let undoOperation = receipt.undo {
            let target = undoOperation.target.flatMap(name).map { " “\($0)”" } ?? ""
            undo = UndoOffer(
                title: "\(undoOperation.title)\(target)",
                expectedRevision: undoOperation.expectedRevision.map { "Expects revision \($0)" } ?? ""
            )
            noUndoReason = nil
        } else {
            undo = nil
            noUndoReason = if !isCommitted {
                "Nothing changed, so there is nothing to undo."
            } else if kind == .resetDemo {
                "Reset Demo has no undo. It changed only demo samples; your own data was not touched."
            } else if kind == .startJob || kind == .updateJob {
                "A job's steps have no undo: the work and files they record cannot be taken back by a receipt."
            } else {
                "This operation offers no undo."
            }
        }
    }
}

extension OperationKind {
    var title: String {
        switch self {
        case .createCollection: "Create Collection"
        case .updateCollection: "Rename Collection"
        case .archiveCollection: "Archive Collection"
        case .restoreCollection: "Restore Collection"
        case .createItem: "Create Item"
        case .updateItem: "Update Item"
        case .archiveItem: "Archive Item"
        case .restoreItem: "Restore Item"
        case .resetDemo: "Reset Demo"
        case .setSession: "Set Session"
        case .scheduleAttention: "Schedule Lab Alert"
        case .cancelLabAlerts: "Cancel Lab Alerts"
        case .restoreLabAlerts: "Restore Lab Alerts"
        case .startJob: "Start Job"
        case .updateJob: "Update Job"
        case .placeAnchor: "Place Object"
        case .moveAnchor: "Move Object"
        case .removeAnchor: "Remove Object"
        }
    }
}

extension DomainOperation {
    /// What the operation does, naming the direction when the kind alone does not (LAB-004).
    var title: String {
        switch self {
        case .setSession(_, _, let running): running ? "Start Session" : "Pause Session"
        case .scheduleAttention(_, let draft): "Schedule \(draft.channel.title)"
        // A job step names itself (LAB-032): the kind alone says only "Update Job".
        case .updateJob(_, _, .checkpoint): "Save Job Checkpoint"
        case .updateJob(_, _, .interrupt): "Stop Job"
        case .updateJob(_, _, .resume): "Resume Job"
        case .updateJob(_, _, .cancel): "Cancel Job"
        case .updateJob(_, _, .fail): "Fail Job"
        case .updateJob(_, _, .succeed): "Finish Job"
        default: kind.title
        }
    }
}

extension AdapterKind {
    var title: String {
        switch self {
        case .appUI: "App UI"
        case .appIntent: "App Intent"
        case .shareExtension: "Share extension"
        case .authorizedPeer: "Authorized peer"
        case .modelTool: "Model tool"
        }
    }
}

extension EntityKind {
    var title: String {
        switch self {
        case .collection: "Collection"
        case .item: "Item"
        case .session: "Session"
        case .attention: "Lab alert"
        case .job: "Job"
        case .anchor: "Placed Object"
        }
    }
}
