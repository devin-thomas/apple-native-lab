import LabSupport
import Observation

/// Probe results for the Readiness screen.
///
/// Holds a `CapabilityRegistry` only, which has no way to ask for a permission, so showing or
/// refreshing this board can never prompt. Results arrive one capability at a time.
@MainActor
@Observable
final class CapabilityBoard {
    let probed: [Capability]
    let excluded: [CapabilityReport]
    private(set) var reports: [Capability: CapabilityReport] = [:]
    private(set) var isProbing = false
    private let registry: CapabilityRegistry

    init(registry: CapabilityRegistry = .live()) {
        self.registry = registry
        probed = registry.probed
        excluded = registry.excludedReports()
    }

    /// The probed capabilities counted by readiness, in badge order, as one sentence.
    var summary: CountSummary {
        let measured = probed.compactMap { reports[$0]?.readiness }
        let parts = CapabilityReadiness.allCases.map { readiness in
            CountSummary.Part(count: measured.count { $0 == readiness }, label: readiness.summaryLabel)
        }
        return CountSummary(
            total: probed.count, singular: "capability", plural: "capabilities",
            parts: parts + [CountSummary.Part(count: probed.count - measured.count, label: "still probing")]
        )
    }

    func refresh() async {
        guard !isProbing else { return }
        isProbing = true
        defer { isProbing = false }
        let registry = registry
        await withTaskGroup(of: CapabilityReport.self) { group in
            for capability in probed {
                group.addTask { await registry.report(for: capability) }
            }
            for await report in group {
                reports[report.capability] = report
            }
        }
    }
}

extension CapabilityReadiness {
    /// The readiness as it reads after a count: "2 waiting for an action".
    var summaryLabel: String {
        switch self {
        case .available: "available"
        case .needsAction: "waiting for an action"
        case .unknown: "not measurable here"
        case .denied: "declined"
        case .unavailable: "unavailable"
        }
    }
}
