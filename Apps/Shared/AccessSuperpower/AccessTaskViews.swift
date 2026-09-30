import AccessSuperpower
import LabDomain
import SwiftUI

/// The task: its question, what to do, and where it stands, as a word and a symbol.
struct AccessTaskHeader: View {
    let status: TaskStatus
    let tally: ArchiveTally

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AccessibleTask.question)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(AccessibleTask.instruction)
                .fixedSize(horizontal: false, vertical: true)
            StatusBadge(status: status.descriptor)
            CountSummaryText(summary: CountSummary(
                total: tally.totalSamples, singular: "demo sample", plural: "demo samples",
                parts: [
                    .init(count: tally.totalArchived, label: "archived"),
                    .init(count: tally.totalSamples - tally.totalArchived, label: "not archived"),
                ]
            ))
        }
        .padding(.vertical, 4)
    }
}

extension TaskStatus {
    var descriptor: StatusDescriptor {
        StatusDescriptor(kind: "Task", title: title, symbol: symbol, tone: tone)
    }

    private var tone: StatusTone {
        switch self {
        case .nothingArchived: .neutral
        case .toDo: .active
        case .done: .success
        }
    }
}

/// The chart's text summary: the answer first, then every collection's count. The same sentence is
/// the Audio Graph's summary.
struct ChartSummaryText: View {
    let tally: ArchiveTally

    var body: some View {
        // Not selectable: on the Mac a selectable text keeps its first value for assistive
        // technology after the text changes.
        Text(ChartSemantics.summary(of: tally))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A collection in the list of archived samples: its name, and its count as the chart shows it.
/// One heading element, read like the chart's bar.
struct ArchiveSectionHeader: View {
    let collection: CollectionTally
    let tally: ArchiveTally
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Side by side normally; stacked at accessibility sizes, so no word breaks.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        layout {
            Text(collection.title)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if tally.isLeader(collection) {
                    Image(systemName: "star.fill")
                }
                Text("\(collection.archivedCount) of \(collection.total) archived")
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(collection.title), \(ChartSemantics.barValue(collection, in: tally))")
        .accessibilityAddTraits(.isHeader)
    }
}

/// One archived sample: its title and note, read as one element that says it is archived.
struct ArchivedSampleRow: View {
    let sample: LabItem
    let collectionTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sample.title.value)
                .font(.headline)
            if !sample.note.value.isEmpty {
                Text(sample.note.value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(sample, in: collectionTitle))
    }

    /// Title, collection, then "Archived", separated by commas.
    static func spoken(_ sample: LabItem, in collectionTitle: String) -> String {
        [sample.title.value, collectionTitle, "Archived", sample.note.value.isEmpty ? nil : sample.note.value]
            .compactMap(\.self).joined(separator: ", ")
    }
}

/// Restores one sample. Visible as "Restore"; spoken and named for Voice Control with the sample.
struct RestoreSampleButton: View {
    let sample: LabItem
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button("Restore", systemImage: "arrow.uturn.backward", action: action)
            .disabled(!isEnabled)
            .accessibilityLabel("Restore \(sample.title.value)")
            .accessibilityInputLabels(["Restore \(sample.title.value)", "Restore"])
            .accessibilityHint("Returns the sample to its collection. The receipt offers an undo.")
    }
}

/// What the last restore meant for the task, or why the last change did not happen.
struct AccessResultText: View {
    let outcome: AccessTaskSession.Outcome?
    let message: String?

    var body: some View {
        if let outcome {
            Label {
                Text(outcome.task.sentence)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: outcome.task.completesTask ? "checkmark.circle" : "exclamationmark.circle")
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        }
        if let message {
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The experiment's own fixture state: archive the practice samples, or restore them.
struct PracticeControls: View {
    let session: AccessTaskSession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        let counts = session.practiceCounts(in: library)
        let total = PracticeSet.standard.sampleIDs.count
        VStack(alignment: .leading, spacing: 10) {
            Text("Practice archives \(total) demo samples, so the chart has something to compare. Each change has its own receipt and undo. Reset Practice restores only those samples; your own data is never touched.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set Up Practice", systemImage: "archivebox") {
                session.setUpPractice(in: library)
            }
            .disabled(counts.toArchive == 0 || !session.canRestore(in: library))
            .accessibilityHint(counts.toArchive == 0
                ? "Every practice sample is already archived."
                : "Archives \(counts.toArchive) demo samples, each with its own receipt.")
            Button("Reset Practice", systemImage: "arrow.counterclockwise") {
                session.resetPractice(in: library)
            }
            .disabled(counts.toRestore == 0 || !session.canRestore(in: library))
            .accessibilityHint(counts.toRestore == 0
                ? "No practice sample is archived."
                : "Restores \(counts.toRestore) practice samples. Nothing else changes.")
        }
    }
}

/// The four ways to finish the task on this host, the declared fallback, and the route this
/// build takes.
struct InteractionAlternativesList: View {
    let host: InteractionAlternative.Host
    @Environment(\.accessSonification) private var route

    var body: some View {
        ForEach(InteractionAlternative.allCases) { alternative in
            VStack(alignment: .leading, spacing: 4) {
                Label(alternative.title, systemImage: alternative.symbol)
                    .font(.subheadline.weight(.semibold))
                Text(alternative.steps(on: host))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
        VStack(alignment: .leading, spacing: 4) {
            Label("Without the chart", systemImage: "list.bullet")
                .font(.subheadline.weight(.semibold))
            Text(InteractionAlternative.fallback)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        Text("Every way restores through the lab's operation service as the app, and leaves the same receipt with an undo. \(route.explanation)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A rotor entry for one archived sample: its title and collection.
struct ArchivedSampleRotorEntry: Identifiable {
    let id: ItemID
    let label: String

    static func entries(_ tally: ArchiveTally, matching keep: (LabItem) -> Bool = { _ in true }) -> [ArchivedSampleRotorEntry] {
        tally.collections.flatMap { collection in
            collection.archived.filter(keep).map {
                ArchivedSampleRotorEntry(id: $0.id, label: "\($0.title.value), \(collection.title)")
            }
        }
    }
}
