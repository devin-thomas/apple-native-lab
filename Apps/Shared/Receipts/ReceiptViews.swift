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

/// Committed or not, as a word and a symbol, spoken as "Status: <word>".
struct ReceiptStatusLabel: View {
    let presentation: ReceiptPresentation

    var body: some View {
        StatusLabel(status: presentation.statusDescriptor)
    }
}

extension ReceiptPresentation {
    var statusDescriptor: StatusDescriptor {
        StatusDescriptor(
            kind: "Status", title: status,
            symbol: isCommitted ? "checkmark.circle" : "exclamationmark.triangle",
            tone: isCommitted ? .success : .attention
        )
    }
}

/// Every field of one receipt: status and summary, the undo offer if there is one, then operation
/// and request IDs and each affected entity with its revisions.
///
/// On iPhone the Undo button is pinned above the tab bar, so it is reachable without scrolling at
/// every text size; the Undo section above the details still says what the undo does.
struct ReceiptDetailView: View {
    let record: ReceiptRecord
    @Environment(LabLibrary.self) private var library

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
        #if os(iOS)
        .safeAreaInset(edge: .bottom) {
            if let undo = presentation.undo, library.undone[record.id] == nil {
                PinnedActionBar {
                    UndoButton(record: record, offer: undo)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        #endif
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

/// What the undo does and, once used, what it did. On the Mac the Undo button sits here too; on
/// iPhone it is pinned at the bottom of the receipt instead.
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
                let result = library.receipt(id: undoneBy)?.receipt.summary
                    ?? "Operation \(undoneBy.description.prefix(8))."
                Label("Undone: \(result)", systemImage: "arrow.uturn.backward.circle")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                #if os(macOS)
                UndoButton(record: record, offer: offer)
                #endif
            }
        }
        .padding(.vertical, 2)
    }
}

/// Submits a receipt's undo offer as a new request and announces the result. Voice Control
/// accepts "Undo" as well as the full label, which names what the undo restores.
struct UndoButton: View {
    let record: ReceiptRecord
    let offer: ReceiptPresentation.UndoOffer
    @Environment(LabLibrary.self) private var library

    var body: some View {
        Button("Undo", systemImage: "arrow.uturn.backward") {
            Task {
                let result = await library.undo(record)
                LabAnnouncement.outcome(of: result, in: library)?.post()
            }
        }
        .disabled(!library.canAct || library.undone[record.id] != nil)
        .accessibilityLabel("Undo: \(offer.title)")
        .accessibilityInputLabels(["Undo", "Undo \(offer.title)"])
        .accessibilityHint("Submits the undo as a new request with its own receipt.")
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
