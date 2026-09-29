import LabCatalog
import LabSupport
import SwiftUI

/// What this binary is and where it is running, with unmeasured capabilities left unknown.
struct ReadinessView: View {
    let model: LabModel

    var body: some View {
        Form {
            Section("This build") {
                LabeledContent("Version", value: "\(model.provenance.appVersion) (\(model.provenance.buildNumber))")
                LabeledContent("Source revision", value: model.provenance.sourceRevision)
                LabeledContent("Build profile", value: model.provenance.buildProfile)
                LabeledContent("SDK", value: model.provenance.sdkName)
                LabeledContent("Xcode", value: "\(model.provenance.xcodeVersion) (\(model.provenance.xcodeBuild))")
                LabeledContent("Minimum OS", value: model.provenance.minimumOS)
                LabeledContent("Feature level", value: model.featureLevel.rawValue)
            }
            Section("This device") {
                LabeledContent("Platform", value: model.device.platform)
                LabeledContent("OS", value: model.device.osVersion)
                LabeledContent("Model", value: model.device.modelIdentifier)
                LabeledContent("Environment", value: model.device.environment == .physical ? "Physical device" : "Simulator")
                LabeledContent("Memory", value: "\(model.device.memoryGigabytes) GB")
                LabeledContent("Processor cores", value: "\(model.device.processorCount)")
            }
            Section {
                Label("Not measured yet", systemImage: "questionmark.circle")
            } header: {
                Text("Capability probes")
            } footer: {
                Text("Camera, intelligence, networking, and other probes arrive with CORE-004. Until a probe runs, nothing here is shown as ready.")
            }
            if let catalog = model.catalog {
                Section("First release journey") {
                    let progress = catalog.progress(for: .m1)
                    LabeledContent("Experiments running", value: "\(progress.live) of \(progress.total)")
                    ForEach(catalog.experiments(in: .m1)) { experiment in
                        ExperimentRow(experiment: experiment)
                    }
                }
            } else if let error = model.catalogError {
                Section("Catalog") {
                    Label("The bundled catalog failed to load: \(error)", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Readiness")
    }
}
