import LabCatalog
import LabSupport
import SwiftUI

/// What this binary is, where it is running, and what its no-prompt probes measured.
struct ReadinessView: View {
    let model: LabModel
    @State private var capabilities = CapabilityBoard()
    @Environment(\.scenePhase) private var scenePhase

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
                CountSummaryText(summary: capabilities.summary)
                ForEach(capabilities.probed) { capability in
                    CapabilityRow(capability: capability, report: capabilities.reports[capability])
                }
            } header: {
                Text("Capability probes")
            } footer: {
                Text("Probes read status without asking for any permission; an experiment asks only when you start an action that needs it. They report availability, not verification: a capability becomes device-verified only with recorded evidence.")
            }
            if !capabilities.excluded.isEmpty {
                Section {
                    ForEach(capabilities.excluded) { report in
                        CapabilityRow(capability: report.capability, report: report)
                    }
                } header: {
                    Text("Not on this platform")
                } footer: {
                    Text("This build does not compile these frameworks. Each still has an alternate route.")
                }
            }
            if let registry = model.registry {
                Section("First release journey") {
                    let progress = registry.progress(for: .m1)
                    LabeledContent("Experiments running", value: "\(progress.live) of \(progress.total)")
                    ForEach(registry.experiments(in: .milestone(.m1))) { experiment in
                        ExperimentRow(experiment: experiment)
                    }
                }
            } else if let error = model.registryError {
                Section("Catalog") {
                    Label("The bundled catalog failed to load: \(error)", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Readiness")
        .toolbar {
            ToolbarItem {
                Button("Probe Again", systemImage: "arrow.clockwise") {
                    Task { await capabilities.refresh() }
                }
                .keyboardShortcut("r")
                .disabled(capabilities.isProbing)
                .help("Read every capability status again without prompting (⌘R)")
            }
        }
        .task { await capabilities.refresh() }
        .onChange(of: scenePhase) { _, phase in
            // A permission changed in Settings shows up when the person returns.
            if phase == .active { Task { await capabilities.refresh() } }
        }
    }
}
