import AccessSuperpower
import LabCatalog
import LabDomain
import SwiftUI

/// Access as a Superpower on one page: the task, the chart with its summary, then the declared
/// fallback, a semantic list of every collection's archived samples with a Restore button on each,
/// the result and its receipt, practice data, and the four ways to finish.
///
/// iPhone and iPad push it from the experiment's catalog page. The Mac shows the same parts in its
/// window columns instead (`Apps/Mac/Window/AccessSuperpowerColumns.swift`).
struct AccessSuperpowerPage: View {
    @Environment(LabLibrary.self) private var library
    @State private var session: AccessTaskSession

    /// - Parameter session: A new session for the page by default. The Mac hosted tests pass one
    ///   they can read, so every way of finishing the task is judged by the same session.
    init(session: AccessTaskSession = AccessTaskSession()) {
        _session = State(initialValue: session)
    }

    var body: some View {
        let tally = AccessTaskSession.tally(library)
        let canRestore = session.canRestore(in: library)
        List {
            Section {
                AccessTaskHeader(status: session.status(in: library), tally: tally)
            }
            Section {
                ChartSummaryText(tally: tally)
                ArchiveChart(tally: tally) { restore($0) }
            } header: {
                Text(ChartSemantics.chartTitle)
            }
            ForEach(tally.collections) { collection in
                Section {
                    if collection.archived.isEmpty {
                        Text("No archived samples.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(collection.archived) { sample in
                        ArchivedSampleListRow(sample: sample, collectionTitle: collection.title, isEnabled: canRestore) {
                            restore(sample.id)
                        }
                    }
                } header: {
                    ArchiveSectionHeader(collection: collection, tally: tally)
                }
            }
            let outcome = session.currentOutcome(in: library)
            if outcome != nil || session.message != nil {
                Section("Result") {
                    AccessResultText(outcome: outcome, message: session.message)
                    if let record = outcome?.record {
                        NavigationLink {
                            ReceiptDetailView(record: record)
                                .navigationTitle("Receipt")
                                #if os(iOS)
                                .navigationBarTitleDisplayMode(.inline)
                                #endif
                        } label: {
                            ReceiptRow(record: record)
                        }
                    }
                }
            }
            Section("Practice data") {
                PracticeControls(session: session)
            }
            Section("Four ways to finish") {
                InteractionAlternativesList(host: .phone)
            }
        }
        .accessibilityRotor("Archived Samples", entries: ArchivedSampleRotorEntry.entries(tally), entryID: \.id, entryLabel: \.label)
        .overlay {
            if library.collections.isEmpty { LibraryPhaseView() }
        }
        .navigationTitle(AccessSuperpowerExperiment.title)
        .onDisappear { session.cancelPractice() }
    }

    private func restore(_ id: ItemID) {
        Task { await session.restore(id, in: library) }
    }
}

/// An archived sample with its Restore button beside it, or below it at accessibility sizes so
/// neither the title nor the button truncates.
private struct ArchivedSampleListRow: View {
    let sample: LabItem
    let collectionTitle: String
    let isEnabled: Bool
    let restore: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            ArchivedSampleRow(sample: sample, collectionTitle: collectionTitle)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            // Prominent: the audit fails contrast on a bordered button's tinted title.
            RestoreSampleButton(sample: sample, isEnabled: isEnabled, action: restore)
                .buttonStyle(.borderedProminent)
                .labelStyle(.titleAndIcon)
        }
    }
}

/// The experiment's entry on its catalog page: iPhone and iPad push the experiment, and the Mac
/// shows it in the frontmost window (also in the sidebar and with Command-5). Shown only on
/// LAB-035's page.
struct AccessSuperpowerLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    /// The window showing this page. A focused value does not reach a view, so the window puts
    /// itself in the environment.
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == AccessSuperpowerExperiment.id {
            #if os(macOS)
            Button {
                window?.destination = .accessSuperpower
            } label: {
                Label("Open \(AccessSuperpowerExperiment.title)", systemImage: AccessSuperpowerExperiment.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌘5)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                AccessSuperpowerPage()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(AccessSuperpowerExperiment.title)", systemImage: AccessSuperpowerExperiment.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            // A rounded rectangle, not a capsule: at accessibility sizes the title takes several lines.
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .accessibilityHint("Opens the experiment.")
            #endif
        }
    }
}
