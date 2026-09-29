import LabCatalog
import SwiftUI

enum CatalogScope: Hashable {
    case all
    case milestone(Milestone)
    case category(String)

    var title: String {
        switch self {
        case .all: "All Experiments"
        case .milestone(let milestone): "\(milestone.rawValue) · \(milestone.title)"
        case .category(let category): category
        }
    }
}

struct CatalogSplitView: View {
    let model: LabModel
    @State private var scope: CatalogScope? = .milestone(.m1)
    @State private var selection: ExperimentDescriptor.ID?
    @State private var query = ""
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(selection: $scope) {
                Label("All Experiments", systemImage: "square.grid.2x2").tag(CatalogScope.all)
                Section("Milestones") {
                    ForEach(Milestone.allCases, id: \.self) { milestone in
                        Label(CatalogScope.milestone(milestone).title, systemImage: "flag")
                            .tag(CatalogScope.milestone(milestone))
                    }
                }
                Section("Categories") {
                    ForEach(model.catalog?.categories ?? [], id: \.self) { category in
                        Label(category, systemImage: "folder").tag(CatalogScope.category(category))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } content: {
            List(visibleExperiments, selection: $selection) { experiment in
                ExperimentRow(experiment: experiment)
            }
            .overlay {
                if visibleExperiments.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle(scope?.title ?? "Native Lab")
            .navigationSplitViewColumnWidth(min: 300, ideal: 340)
            .searchable(text: $query, placement: .sidebar, prompt: "Search experiments")
        } detail: {
            if let id = selection, let experiment = model.catalog?.experiment(id: id) {
                ExperimentDetailView(experiment: experiment)
                    .navigationSplitViewColumnWidth(min: 380, ideal: 560)
            } else {
                ContentUnavailableView("Select an Experiment", systemImage: "flask",
                                       description: Text("Every experiment shows its payoff, devices, and build status."))
                    .navigationSplitViewColumnWidth(min: 380, ideal: 560)
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Readiness", systemImage: "gauge.with.dots.needle.33percent") {
                    openWindow(id: "readiness")
                }
                .help("Show this build and device (⇧⌘0)")
            }
        }
    }

    private var visibleExperiments: [ExperimentDescriptor] {
        guard let catalog = model.catalog else { return [] }
        let matches = catalog.search(query)
        switch scope ?? .all {
        case .all: return matches
        case .milestone(let milestone): return matches.filter { $0.milestone == milestone }
        case .category(let category): return matches.filter { $0.category == category }
        }
    }
}
