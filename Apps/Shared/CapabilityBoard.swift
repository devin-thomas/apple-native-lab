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
