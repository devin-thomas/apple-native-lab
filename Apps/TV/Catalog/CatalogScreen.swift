import LabCatalog
import LabSupport
import SwiftUI

/// Every experiment in the lab, by milestone, beside a summary of what this build carries.
///
/// The list is the only focusable column, so Up and Down move through experiments, Select opens
/// one, and Menu from the list returns focus to the tab bar.
struct CatalogScreen: View {
    let host: TVHost

    var body: some View {
        NavigationStack {
            if let registry = host.registry {
                HStack(alignment: .top, spacing: 72) {
                    CatalogSummary(registry: registry, provenance: host.provenance)
                        .frame(width: 520, alignment: .leading)
                    ExperimentList(registry: registry)
                }
                .navigationDestination(for: RegisteredExperiment.self) { experiment in
                    ExperimentDetailScreen(experiment: experiment)
                }
            } else {
                ContentUnavailableView {
                    Label("Catalog Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The catalog bundled with this build did not load (\(host.catalogProblem ?? "unknown error")). Nothing here is live. Readiness still works.")
                }
                .accessibilityIdentifier("catalog.unavailable")
            }
        }
    }
}

/// The lab at a glance. Static text: it describes the bundled snapshot and takes no focus.
private struct CatalogSummary: View {
    let registry: ExperimentRegistry
    let provenance: BuildProvenance

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Native Lab")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 12) {
                Text("\(registry.experiments.count) experiments in \(registry.categories.count) categories")
                    .font(.headline)
                let firstRelease = registry.progress(for: .m1)
                Text("\(firstRelease.live) of \(firstRelease.total) first-release experiments run on the lab's other hosts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(ImplementationState.allCases, id: \.self) { state in
                    let count = registry.count(in: .state(state))
                    if count > 0 {
                        SymbolLabel(title: "\(count) \(state.title)", systemImage: state.symbolName)
                            .font(.callout)
                    }
                }
            }
            SymbolLabel(title: "This Apple TV runs Native Screening Room; every other experiment is unavailable here. It shows \(snapshotDescription).",
                        systemImage: "tv")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catalog.summary")
    }

    /// The catalog is a snapshot taken when this build was made, and says which.
    private var snapshotDescription: String {
        let revision = provenance.sourceRevision
        let build = revision == "unknown" ? "this build" : "build \(revision)"
        return "the catalog bundled with \(build), its sources reviewed \(registry.sourceReview)"
    }
}

/// Experiments grouped by milestone, first release first.
private struct ExperimentList: View {
    let registry: ExperimentRegistry

    var body: some View {
        List {
            ForEach(Milestone.allCases, id: \.self) { milestone in
                let members = registry.experiments(in: .milestone(milestone))
                if !members.isEmpty {
                    Section {
                        ForEach(members) { experiment in
                            NavigationLink(value: experiment) {
                                ExperimentRow(experiment: experiment)
                            }
                            .accessibilityIdentifier("experiment.\(experiment.id)")
                        }
                    } header: {
                        Text("\(milestone.rawValue) · \(milestone.title)")
                    }
                }
            }
        }
        .accessibilityIdentifier("catalog.list")
    }
}

/// One experiment: its title, then its state as a word and symbol beside its ID and category.
private struct ExperimentRow: View {
    let experiment: RegisteredExperiment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(experiment.title)
                .font(.headline)
            HStack(spacing: 24) {
                SymbolLabel(title: experiment.state.title, systemImage: experiment.state.symbolName)
                Text("\(experiment.id) · \(experiment.category)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(experiment.title), State: \(experiment.state.title), \(experiment.id), \(experiment.category)")
    }
}
