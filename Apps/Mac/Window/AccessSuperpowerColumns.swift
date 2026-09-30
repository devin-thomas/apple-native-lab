import AccessSuperpower
import LabDomain
import SwiftUI

/// The content column for Access as a Superpower: the task, then the declared fallback, a semantic
/// list of every demo collection's archived samples, filtered by the window's search.
///
/// It is the window's results stop, so the keyboard path needs no keyboard navigation: Command-5,
/// Tab to this list, the arrow keys to select a sample, and Return to restore it. Double-click, the
/// context menu, and each row's VoiceOver action restore too.
struct AccessSuperpowerListColumn: View {
    @Bindable var window: MainWindowState
    @Bindable var session: AccessTaskSession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        let tally = AccessTaskSession.tally(library)
        let matches = { (sample: LabItem, collection: CollectionTally) in Self.matches(sample, collection, window.searchText) }
        List(selection: $session.selectedSampleID) {
            Section {
                AccessTaskHeader(status: session.status(in: library), tally: tally)
            }
            ForEach(tally.collections) { collection in
                let shown = collection.archived.filter { matches($0, collection) }
                Section {
                    if shown.isEmpty {
                        Text(collection.archived.isEmpty ? "No archived samples." : "No archived samples match.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shown) { sample in
                        ArchivedSampleRow(sample: sample, collectionTitle: collection.title)
                            .tag(sample.id)
                            .accessibilityAction(named: "Restore \(sample.title.value)") { restore(sample.id) }
                    }
                } header: {
                    ArchiveSectionHeader(collection: collection, tally: tally)
                }
            }
        }
        .contextMenu(forSelectionType: ItemID.self) { selection in
            if let id = selection.first {
                Button("Restore Sample", systemImage: "arrow.uturn.backward") { restore(id) }
                    .disabled(!session.canRestore(in: library))
            }
        } primaryAction: { selection in
            // Return and double-click: the list's own keyboard path to the task's operation.
            if let id = selection.first { restore(id) }
        }
        .accessibilityLabel(listLabel(tally))
        .accessibilityRotor("Archived Samples", entries: ArchivedSampleRotorEntry.entries(tally) { sample in
            tally.sample(sample.id).map { matches(sample, $0.collection) } ?? false
        }, entryID: \.id, entryLabel: \.label)
        .overlay {
            if library.collections.isEmpty { LibraryPhaseView() }
        }
        .navigationTitle(AccessSuperpowerExperiment.title)
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
    }

    private func restore(_ id: ItemID) {
        Task {
            if let record = await session.restore(id, in: library) { window.inspect(record) }
        }
    }

    private func listLabel(_ tally: ArchiveTally) -> String {
        "Archived samples, \(tally.totalArchived == 1 ? "1 sample" : "\(tally.totalArchived) samples")"
    }

    static func matches(_ sample: LabItem, _ collection: CollectionTally, _ text: String) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [sample.title.value, sample.note.value, collection.title].contains { $0.localizedStandardContains(needle) }
    }
}

/// The detail column for Access as a Superpower: the chart with its summary and Audio Graph, the
/// selected sample and its Restore button, the result, practice data, and the four ways to finish.
/// A restore's receipt opens in the window's receipt inspector.
struct AccessSuperpowerDetailColumn: View {
    @Bindable var window: MainWindowState
    let session: AccessTaskSession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        let tally = AccessTaskSession.tally(library)
        Form {
            Section {
                ChartSummaryText(tally: tally)
                ArchiveChart(tally: tally) { restore($0) }
            } header: {
                Text(ChartSemantics.chartTitle)
            }
            Section("Selected sample") {
                selectedSample(tally)
            }
            let outcome = session.currentOutcome(in: library)
            if outcome != nil || session.message != nil {
                Section("Result") {
                    AccessResultText(outcome: outcome, message: session.message)
                    if let record = outcome?.record {
                        Button {
                            window.inspect(record)
                        } label: {
                            ReceiptRow(record: record)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the receipt in the inspector.")
                    }
                }
            }
            Section("Practice data") {
                PracticeControls(session: session)
            }
            Section("Four ways to finish") {
                InteractionAlternativesList(host: .mac)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func selectedSample(_ tally: ArchiveTally) -> some View {
        if let id = session.selectedSampleID, let (sample, collection) = tally.sample(id), sample.isArchived {
            LabeledContent("Sample", value: sample.title.value)
            LabeledContent("Collection", value: collection.title)
            LabeledContent("Status", value: "Archived")
            Button("Restore Sample", systemImage: "arrow.uturn.backward") { restore(id) }
                .disabled(!session.canRestore(in: library))
                .accessibilityLabel("Restore \(sample.title.value)")
                .accessibilityInputLabels(["Restore Sample", "Restore \(sample.title.value)", "Restore"])
                .accessibilityHint("Returns the sample to its collection. The receipt offers an undo.")
        } else {
            Text("Select an archived sample in the list, then press Return or choose Restore Sample. Each bar in the chart also has Restore actions for VoiceOver.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func restore(_ id: ItemID) {
        Task {
            if let record = await session.restore(id, in: library) { window.inspect(record) }
        }
    }
}
