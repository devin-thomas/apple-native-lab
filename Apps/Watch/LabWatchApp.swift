import LabCatalog
import LabSupport
import SwiftUI
import TactileGrammar

@main
struct LabWatchApp: App {
    init() {
        TactileGrammarCenter.shared.install(LiveTactileGrammar.makeEngine())
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}

/// A glanceable answer to "what is on my wrist, and what works yet?"
struct WatchHomeView: View {
    private let catalog = try? ExperimentCatalog.bundled()
    private let provenance = BuildProvenance.current
    private let device = DeviceSnapshot.current

    var body: some View {
        NavigationStack {
            List {
                Section("First release") {
                    if let catalog {
                        let progress = catalog.progress(for: .m1)
                        LabeledContent("Running", value: "\(progress.live) of \(progress.total)")
                        ForEach(catalog.experiments(in: .m1)) { experiment in
                            NavigationLink(value: experiment) {
                                VStack(alignment: .leading) {
                                    Text(experiment.title).font(.headline)
                                    Label(experiment.state.title, systemImage: "doc.text")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Label("Catalog unavailable", systemImage: "exclamationmark.triangle")
                    }
                }
                Section("Tactile Grammar") {
                    if let catalog, let experiment = catalog.experiments.first(where: { $0.id == TactileGrammarExperiment.id }) {
                        NavigationLink(value: experiment) {
                            VStack(alignment: .leading) {
                                Text(experiment.title).font(.headline)
                                Text("Three cues").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("This watch") {
                    LabeledContent("Model", value: device.modelIdentifier)
                    LabeledContent("OS", value: device.osVersion)
                    LabeledContent("Build", value: provenance.sourceRevision)
                    LabeledContent("SDK", value: provenance.sdkName)
                }
            }
            .navigationTitle("Native Lab")
            .navigationDestination(for: ExperimentDescriptor.self) { experiment in
                if experiment.id == TactileGrammarExperiment.id {
                    TactileGrammarWatchPage()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(experiment.id).font(.caption).foregroundStyle(.secondary)
                            Text(experiment.moment)
                            Text("Not built yet.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle(experiment.title)
                }
            }
        }
    }
}
