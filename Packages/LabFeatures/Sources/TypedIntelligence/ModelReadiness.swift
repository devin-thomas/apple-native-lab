import LabSupport

/// Whether the on-device model route is open, read from the CORE-004 probe for
/// `Capability.onDeviceLanguageModel`, and if not, which gate closed it.
///
/// The probe separates hardware (device eligibility), service (Apple Intelligence on, language
/// supported), and asset (model ready). The interface names the failing gates in the probe's own
/// words, then offers the sample parser and the manual editor. Nothing here is device
/// verification: a probe reports availability only.
public struct ModelReadiness: Equatable, Sendable {
    public enum Route: Hashable, Sendable {
        /// Every availability gate is met; the model may be offered.
        case model
        /// At least one gate is not met or not measured. The non-model paths apply.
        case fallback
    }

    public let route: Route
    public let readiness: CapabilityReadiness
    /// The gates that decided the route, each with what the probe read. Empty when open.
    public let failedGates: [CapabilityGate]
    /// The documented alternate route, from the capability registry.
    public let fallback: FallbackRoute

    public init(_ report: CapabilityReport) {
        precondition(report.capability == .onDeviceLanguageModel, "ModelReadiness reads the language model probe")
        readiness = report.readiness
        route = report.route == .live ? .model : .fallback
        failedGates = report.decidingGates
        fallback = report.fallback
    }

    /// Probes this device without prompting.
    public static func probe(_ registry: CapabilityRegistry = .live()) async -> ModelReadiness {
        ModelReadiness(await registry.report(for: .onDeviceLanguageModel))
    }

    /// One sentence naming what closed the route, or `nil` when it is open.
    public var explanation: String? {
        guard route == .fallback else { return nil }
        guard !failedGates.isEmpty else { return "The on-device model's availability could not be read here." }
        return failedGates.map { "\($0.kind.title): \($0.detail)" }.joined(separator: " ")
    }
}
