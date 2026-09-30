import LabCatalog
import LabSupport
import LocalConstellation
import SwiftUI

/// One experiment's record: what it shows, its state, its fallback, and where its sources live.
///
/// The header stays in place; every block below it is a focus card, so Down walks the cards and
/// scrolls them. Menu closes the page and returns focus to the experiment it came from; the page
/// adds no handler of its own.
struct ExperimentDetailScreen: View {
    let experiment: RegisteredExperiment

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            header
                .padding(.horizontal, 80)
            ConstellationTVLaunch(experiment: experiment)
                .padding(.horizontal, 80)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 40, alignment: .top),
                                    GridItem(.flexible(), spacing: 40, alignment: .top)],
                          alignment: .leading, spacing: 40) {
                    FocusCard(identifier: "detail.moment") {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeading(title: "What it shows")
                            Text(experiment.moment)
                        }
                    }
                    FocusCard(identifier: "detail.this-device") {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeading(title: "On this Apple TV")
                            SymbolLabel(title: hasModule ? "Runs here" : "Unavailable here", systemImage: hasModule ? "tv" : "tv.slash")
                                .font(.headline)
                            Text(thisDeviceNote)
                        }
                    }
                    FocusCard(identifier: "detail.fallback") {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeading(title: "When the live path is unavailable")
                            Text(experiment.fallback)
                        }
                    }
                    FocusCard(identifier: "detail.hosts") {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeading(title: "Hosts")
                            Text(experiment.hosts)
                        }
                    }
                    FocusCard(identifier: "detail.apis") {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeading(title: "Primary APIs")
                            Text(experiment.primaryAPIs)
                        }
                    }
                    FocusCard(identifier: "detail.sources") {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeading(title: "Sources in the public repository")
                            ForEach(experiment.sourceLinks) { link in
                                Text("\(link.title): \(link.relativePath)")
                            }
                            if !experiment.dependsOn.isEmpty {
                                Text("Depends on \(experiment.dependsOn.joined(separator: ", ")).")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                // Room inside the scroll bounds for a focused card to grow and cast its shadow;
                // the fixed header above never has cards drawn over it.
                .padding(.horizontal, 80)
                .padding(.vertical, 32)
            }
        }
        .font(.callout)
        .padding(.top, 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("experiment.detail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(experiment.title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 32) {
                SymbolLabel(title: experiment.state.title, systemImage: experiment.state.symbolName)
                    .font(.headline)
                Text("\(experiment.id) · \(experiment.milestone.rawValue) · \(experiment.category)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(experiment.state.meaning)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.header")
    }

    /// Whether this build carries a module for the experiment on Apple TV (LAB-019 so far).
    private var hasModule: Bool { experiment.id == LocalConstellation.experimentID }

    /// Why nothing runs here, in the terms of this experiment's declared hosts.
    private var thisDeviceNote: String {
        if hasModule {
            return "This Apple TV is the display: it joins a conductor on the local network, or runs the whole show as a simulation. Its state describes the lab as a whole, not this Apple TV."
        }
        let hosts = experiment.hosts
        let namesTelevision = hosts.localizedCaseInsensitiveContains("Apple TV")
            || hosts.localizedCaseInsensitiveContains("tvOS")
        let reason = namesTelevision
            ? "Apple TV is one of this experiment's hosts, but this build carries no experiment module yet."
            : "Apple TV is not one of this experiment's hosts."
        return "\(reason) Its state describes the lab as a whole, not this Apple TV."
    }
}
