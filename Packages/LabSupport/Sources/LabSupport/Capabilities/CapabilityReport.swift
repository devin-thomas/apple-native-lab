/// What a probe found for one capability on this device: every gate, and the route to take.
public struct CapabilityReport: Sendable, Equatable, Identifiable {
    public var capability: Capability
    public var platform: LabPlatform
    /// Gates in `GateKind` order. The verification gate is always last.
    public var gates: [CapabilityGate]
    /// `false` when this platform's build does not compile the probe at all.
    public var isProbed: Bool

    public var id: Capability { capability }

    public init(capability: Capability, platform: LabPlatform, gates: [CapabilityGate], isProbed: Bool) {
        self.capability = capability
        self.platform = platform
        self.gates = gates.sorted { $0.kind.order < $1.kind.order }
        self.isProbed = isProbed
    }

    public var readiness: CapabilityReadiness { .combining(gates) }

    /// The gates that decided `readiness`, so the interface can name the reason.
    public var decidingGates: [CapabilityGate] { CapabilityReadiness.decidingGates(gates, for: readiness) }

    public var fallback: FallbackRoute { capability.fallback }

    public var route: CapabilityRoute {
        switch readiness {
        case .available: .live
        case .needsAction: .afterFeatureAction(ifDeclined: fallback)
        case .unknown, .denied, .unavailable: .fallback(fallback)
        }
    }

    public func gate(_ kind: GateKind) -> CapabilityGate? {
        gates.first { $0.kind == kind }
    }

    /// Always `false` for a probe result. Only recorded evidence can verify a capability.
    public var isDeviceVerified: Bool { gate(.verification)?.state == .met }
}

/// Where a feature goes next for a capability.
public enum CapabilityRoute: Sendable, Equatable {
    /// Every availability gate is met. The live adapter may run.
    case live
    /// An explicit feature action must ask or download first. A refusal takes the fallback.
    case afterFeatureAction(ifDeclined: FallbackRoute)
    /// The documented alternate route applies until a later probe says otherwise.
    case fallback(FallbackRoute)

    public var fallbackRoute: FallbackRoute? {
        switch self {
        case .live: nil
        case .afterFeatureAction(let route), .fallback(let route): route
        }
    }
}

extension GateKind {
    var order: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }
}
