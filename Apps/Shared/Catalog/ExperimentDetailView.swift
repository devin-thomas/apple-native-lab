import LabCatalog
import LabSupport
import SwiftUI

/// One experiment's page, in the five areas every experiment has: the payoff, its current state,
/// the primary action, what happens when the live route is unavailable, and how this build runs
/// it. No experiment has a module yet, so the primary action is reading its specification and the
/// route says so plainly.
struct ExperimentDetailView: View {
    /// What this build actually contains for an experiment in each state. Kept to what the
    /// evidence supports: "implemented" never claims a physical device.
    static func buildSummary(for state: ImplementationState) -> String {
        switch state {
        case .specified:
            "In this build: the specification only. The experiment is registered with its state and fallback, but no module runs it yet."
        case .spiked:
            "In this build: an exploratory spike. It shows the mechanism, not a finished feature."
        case .implemented:
            "In this build: a working module runs this experiment. It is proven on the Mac or in the simulator; any physical-device proof is recorded separately in its evidence."
        case .deviceVerified:
            "In this build: a working module, verified on a physical device with recorded evidence."
        case .releaseReady:
            "In this build: a working module that passed its device, accessibility, and privacy checks."
        case .blocked:
            "In this build: the live adapter is blocked. Its fallback is how to use it today."
        }
    }

    let experiment: RegisteredExperiment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                AccessSuperpowerLaunch(experiment: experiment)
                SurfaceDeckLaunch(experiment: experiment)
                ScreeningRoomLaunch(experiment: experiment)
                Text(experiment.moment)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                stateNote
                TypedIntelligenceEntry(experiment: experiment)
                ExperimentModuleAction(experimentID: experiment.id)
                #if os(macOS)
                SpecificationAction(link: experiment.specification)
                #endif
                DetailSection(title: "Fallback", symbol: "arrow.triangle.branch") {
                    Text(experiment.fallback)
                }
                DetailSection(title: "How this works", symbol: "gearshape.2") {
                    Text(Self.buildSummary(for: experiment.state))
                }
                DetailSection(title: "Runs on", symbol: "laptopcomputer.and.iphone") {
                    Text(experiment.hosts)
                }
                DetailSection(title: "Built with", symbol: "shippingbox") {
                    Text(experiment.primaryAPIs)
                }
                if !experiment.dependsOn.isEmpty {
                    DetailSection(title: "Depends on", symbol: "point.3.connected.trianglepath.dotted") {
                        Text(experiment.dependsOn.joined(separator: ", "))
                    }
                }
                DetailSection(title: "Sources", symbol: "link") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(experiment.sourceLinks) { link in
                            SourceLinkRow(link: link)
                        }
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(experiment.title)
        #if os(iOS)
        // The primary action stays pinned and reachable at every text size. The path is listed
        // under Sources, so the bar holds only the button.
        .safeAreaInset(edge: .bottom) {
            PinnedActionBar {
                SpecificationAction(link: experiment.specification, showsPath: false)
            }
        }
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(experiment.id) · \(experiment.category) · \(experiment.milestone.rawValue) \(experiment.milestone.title)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            StateBadge(state: experiment.state)
        }
    }

    @ViewBuilder private var stateNote: some View {
        if !experiment.state.isLive {
            let build = experiment.descriptor.tickets.first ?? "its build ticket"
            let qualify = experiment.descriptor.tickets.last ?? "its qualification ticket"
            Label {
                Text("\(experiment.state.meaning) \(build) builds it and \(qualify) qualifies it on real devices. Until then this page describes the plan, not a working feature.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
                    .accessibilityHidden(true)
            }
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .combine)
        }
    }
}

/// The page's primary action: open the specification in the public repository. The relative path
/// sits beside it, so a reader with a checkout and no network can still find the file.
struct SpecificationAction: View {
    let link: SourceLink
    var showsPath = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = link.url {
                Button {
                    openURL(url)
                } label: {
                    Label("Read the Specification", systemImage: "doc.text.magnifyingglass")
                        #if os(iOS)
                        .frame(maxWidth: .infinity)
                        #endif
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Opens the public repository in your browser.")
                .help("Open \(link.relativePath) on GitHub")
            }
            if showsPath {
                Text(link.relativePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel("Path in the repository: \(link.relativePath)")
            }
        }
    }
}

/// A link to one file in the public repository, with its relative path.
struct SourceLinkRow: View {
    let link: SourceLink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let url = link.url {
                Link(destination: url) {
                    Label(link.title, systemImage: "arrow.up.right.square")
                }
                .accessibilityHint("Opens the public repository in your browser.")
                .help("Open \(link.relativePath) on GitHub")
            } else {
                Text(link.title)
            }
            Text(link.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityLabel("Path: \(link.relativePath)")
        }
    }
}

/// A titled block of the detail page.
struct DetailSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
