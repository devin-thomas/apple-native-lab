import LabCatalog
import LocalModelBench
import SwiftUI

enum LocalModelBenchExperiment {
    static let id = LocalModelBench.experimentID
    static let title = "Local Model Bench"
    static let symbol = "stopwatch"
}

/// The bench: four separate runs, two scores that are not combined, and a record action.
struct LocalModelBenchPage: View {
    @Bindable var session: LocalModelBenchSession
    var searchText = ""
    @Environment(LabLibrary.self) private var library

    var body: some View {
        List {
            Section {
                Text(LocalModelBench.notInferenceLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Runs") {
                ForEach(BenchSlot.allCases) { slot in
                    Button(slot.title) { session.start(slot) }
                        .disabled(session.isRunning)
                }
                if session.isRunning {
                    Button("Cancel") { session.cancel() }
                }
            }
            Section("Scores") {
                scoreRow(.cold)
                scoreRow(.warm)
                Text("Cold and warm scores stay separate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !filteredCases.isEmpty {
                Section("Corpus") {
                    ForEach(filteredCases) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.id)
                            Text(item.prompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Section {
                Button("Record Selected Run") {
                    Task { await session.record(using: library) }
                }
                .disabled(selectedReport == nil)
                Button("Reset Bench Results", role: .destructive) {
                    session.isConfirmingReset = true
                }
            }
            if let message = session.message {
                Section {
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle(LocalModelBenchExperiment.title)
        .confirmationDialog("Reset bench results?", isPresented: $session.isConfirmingReset, titleVisibility: .visible) {
            Button("Reset Bench Results", role: .destructive) {
                Task { await session.reset(using: library) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archives this experiment's recorded reports. Other items stay.")
        }
    }

    private var selectedReport: BenchReport? {
        guard let selection = session.selection else { return nil }
        return session.reports[selection]
    }

    private var filteredCases: [BenchmarkCase] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return EvaluationCorpus.cases }
        return EvaluationCorpus.cases.filter {
            $0.id.localizedStandardContains(text) || $0.prompt.localizedStandardContains(text)
        }
    }

    @ViewBuilder private func scoreRow(_ slot: BenchSlot) -> some View {
        if let report = session.reports[slot] {
            if let score = try? report.score() {
                LabeledContent(slot.title, value: "\(score.medianLatencyNanoseconds) ns, fixture script")
            } else {
                LabeledContent(slot.title, value: "No score")
            }
        } else {
            LabeledContent(slot.title, value: "Not run")
        }
    }
}

/// The selected run's export. It is one phase and one thermal class.
struct LocalModelBenchExport: View {
    let report: BenchReport?

    var body: some View {
        if let report, let text = String(data: (try? report.canonical()) ?? Data(), encoding: .utf8), !text.isEmpty {
            ScrollView {
                Text(text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .navigationTitle(report.phase == .measured ? "Measured, \(report.thermal.rawValue)" : report.phase.rawValue.capitalized)
        } else {
            ContentUnavailableView("No Run Yet", systemImage: LocalModelBenchExperiment.symbol,
                                   description: Text("Run a phase. The export stays one phase and one thermal class."))
        }
    }
}

/// The catalog page's way in. Pushed on iPhone; the sidebar destination on the Mac.
struct LocalModelBenchEntry: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == LocalModelBenchExperiment.id {
            VStack(alignment: .leading, spacing: 6) {
                #if os(iOS)
                NavigationLink {
                    LocalModelBenchScreen()
                } label: {
                    Label("Open \(LocalModelBenchExperiment.title)", systemImage: LocalModelBenchExperiment.symbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                #else
                Button("Open \(LocalModelBenchExperiment.title)", systemImage: LocalModelBenchExperiment.symbol) {
                    window?.destination = .localModelBench
                }
                .controlSize(.large)
                .disabled(window == nil)
                .help("Show Local Model Bench in this window (⌥⌘3)")
                #endif
                Text("Runs in this build: the fixture executor, marked as not inference. No model is loaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The bench on iPhone, reached from the catalog page. There is no tab.
struct LocalModelBenchScreen: View {
    @State private var session = LocalModelBenchSession()

    var body: some View {
        LocalModelBenchPage(session: session)
    }
}
