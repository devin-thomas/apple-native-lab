import LabCatalog
import SwiftUI

/// Where importing will start. Nothing can be imported in this build, and the screen says so
/// instead of offering a control that does nothing. Its one action opens the experiment that will
/// bring the share inbox.
struct ImportTab: View {
    let model: LabModel
    private static let shareInboxID = "LAB-007"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text("Not available in this build")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "tray.and.arrow.down")
                            .accessibilityHidden(true)
                    }
                    if let experiment = model.registry?.experiment(id: Self.shareInboxID) {
                        NavigationLink(value: experiment.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(experiment.title) (\(experiment.id))")
                                    .font(.body.weight(.semibold))
                                Text("Brings the share inbox")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text("The share inbox arrives with Share Ingress Station (\(Self.shareInboxID)). Until then nothing can be imported, and nothing you share reaches this app.")
                        .fixedSize(horizontal: false, vertical: true)
                    if let fallback = model.registry?.experiment(id: Self.shareInboxID)?.fallback {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Planned fallback")
                                .font(.subheadline.weight(.semibold))
                            Text(fallback)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text("Anything imported later goes into your own data, which Reset Demo never changes.")
                }
            }
            .navigationTitle("Import")
            .navigationDestination(for: RegisteredExperiment.ID.self) { id in
                if let experiment = model.registry?.experiment(id: id) {
                    ExperimentDetailView(experiment: experiment)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }
}
