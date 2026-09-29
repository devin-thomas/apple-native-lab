import LabCatalog
import LabSupport
import SwiftUI

/// The catalog on iPhone: experiments grouped by milestone, searchable, and filterable by
/// lifecycle state. The state legend explains all six states, including the empty ones.
struct CatalogTab: View {
    let model: LabModel
    @State private var query = ""
    @State private var stateFilter: ImplementationState?
    @State private var showsLegend = false

    var body: some View {
        NavigationStack {
            Group {
                if let registry = model.registry {
                    list(registry)
                } else {
                    ContentUnavailableView("Catalog Unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(model.registryError ?? "The experiment registry did not load."))
                }
            }
            .navigationTitle("Native Lab")
            .navigationDestination(for: RegisteredExperiment.ID.self) { id in
                if let experiment = model.registry?.experiment(id: id) {
                    ExperimentDetailView(experiment: experiment)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .searchable(text: $query, prompt: "Search experiments")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("States", systemImage: "info.circle") { showsLegend = true }
                        .accessibilityHint("Explains the six lifecycle states and how many experiments are in each.")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    stateMenu
                }
            }
            .sheet(isPresented: $showsLegend) {
                if let registry = model.registry {
                    StateLegendSheet(registry: registry)
                }
            }
        }
    }

    private func list(_ registry: ExperimentRegistry) -> some View {
        let scope: CatalogScope = stateFilter.map(CatalogScope.state) ?? .all
        let matches = registry.experiments(in: scope, matching: query)
        return List {
            if let stateFilter {
                Section {
                    Label("Showing \(stateFilter.title) only", systemImage: stateFilter.symbolName)
                    Button("Show All States") { self.stateFilter = nil }
                }
            }
            ForEach(Milestone.allCases, id: \.self) { milestone in
                let members = matches.filter { $0.milestone == milestone }
                if !members.isEmpty {
                    Section {
                        ForEach(members) { experiment in
                            NavigationLink(value: experiment.id) {
                                ExperimentRow(experiment: experiment)
                            }
                        }
                    } header: {
                        Text("\(milestone.rawValue) · \(milestone.title)")
                    }
                }
            }
        }
        .overlay {
            if matches.isEmpty {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if let stateFilter {
                    ContentUnavailableView("No \(stateFilter.title) Experiments", systemImage: stateFilter.symbolName,
                                           description: Text(stateFilter.meaning))
                }
            }
        }
    }

    private var stateMenu: some View {
        Menu {
            Picker("State", selection: $stateFilter) {
                Text("All States").tag(ImplementationState?.none)
                ForEach(ImplementationState.allCases, id: \.self) { state in
                    Label("\(state.title) (\(model.registry?.count(in: .state(state)) ?? 0))", systemImage: state.symbolName)
                        .tag(Optional(state))
                }
            }
        } label: {
            Label("Filter by State", systemImage: stateFilter == nil
                ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityValue(stateFilter?.title ?? "All states")
    }
}

/// All six lifecycle states, what each promises, and how many experiments are in it.
private struct StateLegendSheet: View {
    let registry: ExperimentRegistry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ImplementationState.allCases, id: \.self) { state in
                        StateLegendRow(state: state, count: registry.count(in: .state(state)))
                    }
                } footer: {
                    Text("A state comes from the experiment's spec and changes only with recorded evidence. A simulator run never makes anything device-verified.")
                }
            }
            .navigationTitle("Lifecycle States")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
