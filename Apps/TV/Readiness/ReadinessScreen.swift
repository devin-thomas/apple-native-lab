import LabSupport
import SwiftUI

/// What this build is, which Apple TV it runs on, and what its no-prompt probes measured.
///
/// Probe Again takes focus first. Each capability is a button that shows or hides its gates, and
/// every other row is a focus card, so the remote reaches every line and Menu returns to the tab bar.
struct ReadinessScreen: View {
    let host: TVHost
    @State private var board = ReadinessBoard()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                probes
                ReadinessSection(title: "This build", footer: nil) {
                    FactsCard(identifier: "readiness.build", facts: buildFacts)
                }
                ReadinessSection(title: "This Apple TV", footer: nil) {
                    FactsCard(identifier: "readiness.device", facts: deviceFacts)
                }
                if !board.excluded.isEmpty {
                    ReadinessSection(title: "Not on this platform",
                                     footer: "This build does not compile these frameworks. Each still has an alternate route.") {
                        ForEach(board.excluded) { report in
                            FocusCard(identifier: "readiness.excluded.\(report.capability.rawValue)") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(report.capability.title).font(.headline)
                                    Text(report.gate(.osAPI)?.detail ?? "Not compiled for this platform.")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .font(.callout)
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .accessibilityIdentifier("readiness")
        .task { await board.refresh() }
        .onChange(of: scenePhase) { _, phase in
            // A reading taken before the app left the screen is stale until it is measured again.
            if phase == .active {
                Task { await board.refresh() }
            } else {
                board.markStale()
            }
        }
    }

    private var probes: some View {
        ReadinessSection(
            title: "Capability probes",
            footer: "Probes read status without asking for any permission, and a Source build declares no purpose string, so it could not ask. They report availability, not verification: a capability becomes device-verified only with recorded evidence."
        ) {
            // One full-width focus section, so Down from the tab bar lands on Probe Again.
            HStack(alignment: .center, spacing: 40) {
                Button("Probe Again", systemImage: "arrow.clockwise") {
                    Task { await board.refresh() }
                }
                .disabled(board.isMeasuring)
                .accessibilityIdentifier("readiness.probe-again")
                FreshnessLine(freshness: board.freshness)
                Spacer(minLength: 0)
            }
            .focusSection()
            ForEach(board.probed) { capability in
                CapabilityButton(capability: capability, report: board.reports[capability],
                                 isStale: isStale)
            }
        }
    }

    private var isStale: Bool {
        if case .stale = board.freshness { return true }
        return false
    }

    private var buildFacts: [(String, String)] {
        let provenance = host.provenance
        return [
            ("Version", "\(provenance.appVersion) (\(provenance.buildNumber))"),
            ("Source revision", provenance.sourceRevision),
            ("Build profile", provenance.buildProfile),
            ("SDK", provenance.sdkName),
            ("Xcode", "\(provenance.xcodeVersion) (\(provenance.xcodeBuild))"),
            ("Minimum OS", provenance.minimumOS),
            ("Feature level", host.featureLevel.rawValue),
        ]
    }

    private var deviceFacts: [(String, String)] {
        let device = host.device
        return [
            ("Platform", device.platform),
            ("OS", device.osVersion),
            ("Model", device.modelIdentifier),
            ("Environment", device.environment == .physical ? "Physical device" : "Simulator"),
            ("Memory", "\(device.memoryGigabytes) GB"),
            ("Processor cores", "\(device.processorCount)"),
        ]
    }
}

/// A titled group of rows with an optional explanation below it.
private struct ReadinessSection<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            content
            if let footer {
                Text(footer)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// When the readings were taken, so a reading never passes for live.
private struct FreshnessLine: View {
    let freshness: ReadinessBoard.Freshness

    var body: some View {
        Group {
            switch freshness {
            case .notMeasured:
                Label("Not measured yet", systemImage: "clock")
            case .measuring:
                Label("Measuring now", systemImage: "ellipsis.circle")
            case .measured(let date):
                Label {
                    Text("Measured \(date, style: .relative) ago, at \(date, style: .time)")
                } icon: {
                    Image(systemName: "clock")
                }
            case .stale(let date):
                Label {
                    Text("Stale: measured at \(date, style: .time), before the app left the screen")
                } icon: {
                    Image(systemName: "clock.badge.exclamationmark")
                }
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("readiness.freshness")
    }
}

/// One probed capability: its readiness and the reason, and on Select every gate and the
/// alternate route.
private struct CapabilityButton: View {
    let capability: Capability
    /// `nil` until the first probe finishes.
    let report: CapabilityReport?
    let isStale: Bool
    @State private var showsGates = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                showsGates.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 32) {
                    Text(capability.title)
                        .font(.headline)
                    Spacer(minLength: 16)
                    if let report {
                        SymbolLabel(title: report.readiness.title, systemImage: report.readiness.symbolName)
                    } else {
                        SymbolLabel(title: "Probing", systemImage: "ellipsis.circle")
                    }
                    Image(systemName: showsGates ? "chevron.down" : "chevron.right")
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
            }
            .disabled(report == nil)
            .accessibilityIdentifier("readiness.probe.\(capability.rawValue)")
            .accessibilityValue(showsGates ? "Gates shown" : "Gates hidden")
            .accessibilityHint("Shows every gate and the alternate route.")

            Text(summary)
                .foregroundStyle(.secondary)
            if showsGates, let report {
                FocusCard(identifier: "readiness.gates.\(capability.rawValue)") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(report.gates, id: \.kind) { gate in
                            Label {
                                Text("\(gate.kind.title): \(gate.stateTitle). \(gate.detail)")
                            } icon: {
                                Image(systemName: gate.state.symbolName)
                            }
                        }
                        if let route = report.route.fallbackRoute {
                            Label("Alternate route: \(route.summary) (\(route.experiments.joined(separator: ", ")))",
                                  systemImage: "arrow.triangle.branch")
                        }
                    }
                }
            }
        }
    }

    private var summary: String {
        guard let report else { return "Reading status without prompting." }
        let reasons = report.decidingGates.map(\.kind.title).joined(separator: ", ")
        let reading = switch report.readiness {
        case .available: "Every measured gate is met. Not device-verified."
        case .needsAction: "Waits for an experiment action: \(reasons)."
        case .unknown: "Not measurable here: \(reasons)."
        case .denied: "Declined: \(reasons). Uses the alternate route."
        case .unavailable: "Not met: \(reasons)."
        }
        return isStale ? "Stale reading. \(reading)" : reading
    }
}

/// A label and value per line, in one focus card.
private struct FactsCard: View {
    let identifier: String
    let facts: [(String, String)]

    var body: some View {
        FocusCard(identifier: identifier) {
            Grid(alignment: .leading, horizontalSpacing: 48, verticalSpacing: 14) {
                ForEach(facts, id: \.0) { label, value in
                    GridRow {
                        Text(label)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}
