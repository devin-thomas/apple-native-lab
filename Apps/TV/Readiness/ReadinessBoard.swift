import Foundation
import LabSupport
import Observation

/// Probe results for the Readiness screen, with an honest age.
///
/// The board holds a `CapabilityRegistry` only, which has no way to ask for a permission, so
/// showing or refreshing it can never prompt. A reading is never presented as live: it carries the
/// time it was taken, and it turns stale when the app leaves the screen until it is measured again.
@MainActor
@Observable
final class ReadinessBoard {
    enum Freshness: Equatable {
        /// Nothing has been measured yet.
        case notMeasured
        /// A probe is running. Earlier readings, if any, stay visible.
        case measuring
        /// Every probed capability was read at this time.
        case measured(Date)
        /// The app left the screen after this reading, so it may no longer be true.
        case stale(Date)
    }

    let probed: [Capability]
    let excluded: [CapabilityReport]
    private(set) var reports: [Capability: CapabilityReport] = [:]
    private(set) var freshness: Freshness = .notMeasured
    private let registry: CapabilityRegistry

    init(registry: CapabilityRegistry = .live()) {
        self.registry = registry
        probed = registry.probed
        excluded = registry.excludedReports()
    }

    var isMeasuring: Bool { freshness == .measuring }

    /// Reads every probed capability again. A second call while one runs does nothing.
    func refresh() async {
        guard !isMeasuring else { return }
        freshness = .measuring
        let results = await registry.probeAll()
        for report in results {
            reports[report.capability] = report
        }
        freshness = .measured(Date())
    }

    /// Marks the current reading stale, for example when the app moves to the background.
    func markStale() {
        if case .measured(let date) = freshness {
            freshness = .stale(date)
        }
    }
}
