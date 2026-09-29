/// Whether a capability can be used now, combined from its availability gates.
///
/// This is availability, not verification. There is deliberately no "verified" case: only a
/// recorded evidence record can establish `device-verified` (SPEC §7).
public enum CapabilityReadiness: String, CaseIterable, Sendable, Codable {
    /// Every availability gate was measured and met.
    case available
    /// Every gate is met or can be satisfied by an explicit feature action.
    case needsAction = "needs-action"
    /// At least one gate could not be measured. Unknown is never ready.
    case unknown
    /// Permission was declined or restricted. The fallback route applies.
    case denied
    /// At least one gate was measured and is not met. The fallback route applies.
    case unavailable

    /// Only a fully measured, fully met capability is ready.
    public var isReady: Bool { self == .available }

    public var title: String {
        switch self {
        case .available: "Available"
        case .needsAction: "Needs action"
        case .unknown: "Unknown"
        case .denied: "Denied"
        case .unavailable: "Unavailable"
        }
    }

    /// Combines gates with fixed precedence. The verification gate is ignored, so a probe can
    /// never make a capability look more trustworthy than availability.
    ///
    /// 1. Any `unmet` gate makes the capability unavailable.
    /// 2. Otherwise any `denied` or `restricted` gate makes it denied.
    /// 3. Otherwise any `unknown` gate makes it unknown.
    /// 4. Otherwise any `needsAction` gate means a feature action must come first.
    /// 5. Otherwise, if at least one gate was measured and all are met, it is available.
    /// 6. No availability gates at all is unknown: nothing measured is not ready.
    public static func combining(_ gates: [CapabilityGate]) -> CapabilityReadiness {
        let states = gates.filter { $0.kind != .verification }.map(\.state)
        if states.isEmpty { return .unknown }
        if states.contains(.unmet) { return .unavailable }
        if states.contains(.denied) || states.contains(.restricted) { return .denied }
        if states.contains(.unknown) { return .unknown }
        if states.contains(.needsAction) { return .needsAction }
        return .available
    }

    /// The gates that decided a readiness value, so the interface can name the reason.
    public static func decidingGates(
        _ gates: [CapabilityGate],
        for readiness: CapabilityReadiness
    ) -> [CapabilityGate] {
        let deciding: Set<GateState> = switch readiness {
        case .available: []
        case .needsAction: [.needsAction]
        case .unknown: [.unknown]
        case .denied: [.denied, .restricted]
        case .unavailable: [.unmet]
        }
        return gates.filter { $0.kind != .verification && deciding.contains($0.state) }
    }
}
