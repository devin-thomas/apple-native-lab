import LabSupport
import SwiftUI

/// One capability: readiness and its deciding gates up front, every gate and the alternate
/// route on request. State is always text plus a symbol, never color alone.
///
/// The toggle is a plain button rather than a `DisclosureGroup`: in a grouped Mac form the
/// disclosure row exposed no accessibility action, so VoiceOver could not open it.
struct CapabilityRow: View {
    let capability: Capability
    /// `nil` while the probe is still running.
    let report: CapabilityReport?
    @State private var showsGates = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) { showsGates.toggle() }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                header
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(showsGates ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(report == nil)
        .accessibilityElement(children: .combine)
        .accessibilityValue(showsGates ? "Gates shown" : "Gates hidden")
        .accessibilityHint("Shows every gate and the alternate route.")

        if showsGates, let report {
            // Gate kinds repeat across capabilities in one form section, so each row's
            // identity includes the capability. Without it the form reused another
            // capability's row.
            ForEach(report.gates.map { GateLine(capability: capability, gate: $0) }) { line in
                GateRow(gate: line.gate)
            }
            if let route = report.route.fallbackRoute {
                FallbackRow(route: route, readiness: report.readiness)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title
                    Spacer(minLength: 8)
                    badge
                }
                VStack(alignment: .leading, spacing: 6) {
                    title
                    badge
                }
            }
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private var title: some View {
        Text(capability.title)
            .font(.headline)
    }

    @ViewBuilder private var badge: some View {
        if let report {
            ReadinessBadge(readiness: report.readiness)
        } else {
            StatusLabel(status: StatusDescriptor(kind: "Readiness", title: "Probing", symbol: "ellipsis.circle", tone: .neutral))
        }
    }

    private var summary: String {
        guard let report else { return "Reading status without prompting." }
        let reasons = report.decidingGates.map(\.kind.title).joined(separator: ", ")
        return switch report.readiness {
        case .available: "Every measured gate is met. Not device-verified."
        case .needsAction: "Waits for an experiment action: \(reasons)."
        case .unknown: "Not measurable here: \(reasons)."
        case .denied: "Declined: \(reasons). Uses the alternate route."
        case .unavailable: "Not met: \(reasons)."
        }
    }
}

private struct GateLine: Identifiable {
    let capability: Capability
    let gate: CapabilityGate
    var id: String { "\(capability.rawValue).\(gate.kind.rawValue)" }
}

private struct GateRow: View {
    let gate: CapabilityGate

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(gate.kind.title): \(gate.stateTitle)")
                    .font(.subheadline.weight(.semibold))
                Text(gate.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: gate.state.symbolName)
                .foregroundStyle(gate.state.tint)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FallbackRow: View {
    let route: FallbackRoute
    let readiness: CapabilityReadiness

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(readiness == .needsAction ? "If declined" : "Alternate route")
                    .font(.subheadline.weight(.semibold))
                Text("\(route.summary) (\(route.experiments.joined(separator: ", ")))")
                    .font(.footnote)
            }
        } icon: {
            Image(systemName: "arrow.triangle.branch")
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Readiness as a shared status badge, spoken as "Readiness: <word>".
struct ReadinessBadge: View {
    let readiness: CapabilityReadiness

    var body: some View {
        StatusBadge(status: readiness.status)
    }
}

extension CapabilityReadiness {
    var status: StatusDescriptor {
        StatusDescriptor(kind: "Readiness", title: title, symbol: symbolName, tone: tone)
    }

    var symbolName: String {
        switch self {
        case .available: "checkmark.circle"
        case .needsAction: "hand.tap"
        case .unknown: "questionmark.circle"
        case .denied: "hand.raised.slash"
        case .unavailable: "xmark.octagon"
        }
    }

    var tone: StatusTone {
        switch self {
        case .available: .success
        case .needsAction: .active
        case .unknown: .neutral
        case .denied: .attention
        case .unavailable: .critical
        }
    }

    var tint: Color { tone.color }
}

extension GateState {
    var symbolName: String {
        switch self {
        case .met: "checkmark.circle.fill"
        case .needsAction: "hand.tap"
        case .denied: "hand.raised.slash"
        case .restricted: "lock"
        case .unmet: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var tone: StatusTone {
        switch self {
        case .met: .success
        case .needsAction: .active
        case .denied, .restricted: .attention
        case .unmet: .critical
        case .unknown: .neutral
        }
    }

    var tint: Color { tone.color }
}

extension CapabilityGate {
    var stateTitle: String {
        switch (kind, state) {
        case (.verification, .unknown): "No device evidence"
        case (.permission, .needsAction): "Not asked yet"
        case (.asset, .needsAction): "Download needed"
        case (_, .met): "Met"
        case (_, .needsAction): "Needs action"
        case (_, .denied): "Denied"
        case (_, .restricted): "Restricted"
        case (_, .unmet): "Not met"
        case (_, .unknown): "Unknown"
        }
    }
}
