import LabCatalog
import SwiftUI

struct CatalogListView: View {
    let model: LabModel
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(Milestone.allCases, id: \.self) { milestone in
                    let members = matches.filter { $0.milestone == milestone }
                    if !members.isEmpty {
                        Section {
                            ForEach(members) { experiment in
                                NavigationLink(value: experiment) {
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
                if let error = model.catalogError {
                    ContentUnavailableView("Catalog Unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Native Lab")
            .navigationDestination(for: ExperimentDescriptor.self) { experiment in
                ExperimentDetailView(experiment: experiment)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .searchable(text: $query, prompt: "Search experiments")
        }
    }

    private var matches: [ExperimentDescriptor] {
        model.catalog?.search(query) ?? []
    }
}
