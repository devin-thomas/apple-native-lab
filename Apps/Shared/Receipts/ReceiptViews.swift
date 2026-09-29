import LabDomain
import SwiftUI

/// A receipt in a list: what ran, whether it applied, and its summary.
struct ReceiptRow: View {
    let record: ReceiptRecord

    var body: some View {
        let presentation = ReceiptPresentation(record)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(presentation.operation)
                    .font(.headline)
                Spacer(minLength: 4)
                Text(record.recordedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ReceiptStatusLabel(presentation: presentation)
            Text(presentation.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Committed or not, as a word and a symbol.
struct ReceiptStatusLabel: View {
    let presentation: ReceiptPresentation

    var body: some View {
        Label(presentation.status, systemImage: presentation.isCommitted ? "checkmark.circle" : "exclamationmark.triangle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(presentation.isCommitted ? Color.green : Color.orange)
            .accessibilityLabel("Status: \(presentation.status)")
    }
}

/// Every field of one receipt: status and summary, the undo offer if there is one, then operation
/// and request IDs and each affected entity with its revisions.
struct ReceiptDetailView: View {
    let record: ReceiptRecord

    var body: some View {
        let presentation = ReceiptPresentation(record)
        Form {
            Section {
                ReceiptStatusLabel(presentation: presentation)
                Text(presentation.summary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(presentation.operation)
            }
            // The one action a receipt offers comes before the details, so large text never
            // pushes it out of reach.
            Section("Undo") {
                if let undo = presentation.undo {
                    UndoOfferRow(record: record, offer: undo)
                } else if let reason = presentation.noUndoReason {
                    Text(reason)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Request") {
                LabeledContent("Entry point", value: presentation.adapter)
                IdentifierRow(title: "Operation ID", value: presentation.operationID)
                IdentifierRow(title: "Request ID", value: presentation.requestID)
                LabeledContent("Recorded") {
                    Text(record.recordedAt, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                }
            }
            Section(presentation.changes.isEmpty ? "Affected entities" : "Affected entities (\(presentation.changes.count))") {
                if presentation.changes.isEmpty {
                    Text("None. Nothing was changed.")
                        .foregroundStyle(.secondary)
                }
                ForEach(presentation.changes) { line in
                    EntityLineRow(line: line)
                }
            }
            if !presentation.removals.isEmpty {
                Section("Removed (\(presentation.removals.count))") {
                    ForEach(presentation.removals) { line in
                        EntityLineRow(line: line)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct IdentifierRow: View {
    let title: String
    let value: String

    var body: some View {
        // Label above value, so a 36-character identifier never widens a narrow inspector.
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct EntityLineRow: View {
    let line: ReceiptPresentation.EntityLine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: line.reference.kind == .collection ? "folder" : "doc")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(line.name ?? line.kind)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(line.revision)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text("\(line.kind) \(line.reference.rawID.uuidString)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.spokenDescription)
    }
}

private struct UndoOfferRow: View {
    let record: ReceiptRecord
    let offer: ReceiptPresentation.UndoOffer
    @Environment(LabLibrary.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(offer.title)
                .font(.subheadline.weight(.semibold))
            if !offer.expectedRevision.isEmpty {
                Text("\(offer.expectedRevision). If it changed since, the undo is refused and nothing moves.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let undoneBy = library.undone[record.id] {
                Label("Undone by operation \(undoneBy.description.prefix(8))…", systemImage: "arrow.uturn.backward.circle")
                    .font(.footnote)
                    .accessibilityLabel("Already undone by operation \(undoneBy.description.prefix(8))")
            } else {
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    Task { await library.undo(record) }
                }
                .disabled(!library.canAct)
                .accessibilityLabel("Undo: \(offer.title)")
                .accessibilityHint("Submits the undo as a new request with its own receipt.")
            }
        }
        .padding(.vertical, 2)
    }
}

/// The receipts from this session, newest first, each opening its full detail.
struct ReceiptListContent: View {
    @Environment(LabLibrary.self) private var library

    var body: some View {
        if library.receipts.isEmpty {
            ContentUnavailableView(
                "No Receipts Yet", systemImage: "list.bullet.rectangle",
                description: Text("Every change made this session leaves a receipt here. Archive a sample or reset the demo to see one.")
            )
        } else {
            List(library.receipts) { record in
                NavigationLink(value: record.id) {
                    ReceiptRow(record: record)
                }
            }
        }
    }
}
