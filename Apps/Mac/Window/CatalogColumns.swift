import LabCatalog
import LabSupport
import SwiftUI

/// The content column for a catalog scope: matching experiments, or why there are none.
struct CatalogListColumn: View {
    let registry: ExperimentRegistry
    let scope: CatalogScope
    @Bindable var window: MainWindowState

    var body: some View {
        let experiments = registry.experiments(in: scope, matching: window.searchText)
        List(experiments, selection: $window.experimentID) { experiment in
            ExperimentRow(experiment: experiment)
        }
        .overlay {
            if experiments.isEmpty {
                if !window.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView.search(text: window.searchText)
                } else if case .state(let state) = scope {
                    ContentUnavailableView(
                        "No \(state.title) Experiments", systemImage: state.symbolName,
                        description: Text(state.meaning)
                    )
                } else {
                    ContentUnavailableView("No Experiments", systemImage: "flask")
                }
            }
        }
        .navigationTitle(scope.title)
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
    }
}

/// The detail column for the catalog: the selected experiment's page.
struct CatalogDetailColumn: View {
    let registry: ExperimentRegistry
    let experimentID: RegisteredExperiment.ID?

    var body: some View {
        if let experimentID, let experiment = registry.experiment(id: experimentID) {
            ExperimentDetailView(experiment: experiment)
        } else {
            ContentUnavailableView(
                "Select an Experiment", systemImage: "flask",
                description: Text("Every experiment shows its payoff, state, fallback, and sources.")
            )
        }
    }
}
