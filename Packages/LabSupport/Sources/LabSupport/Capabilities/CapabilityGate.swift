/// One independent requirement a capability must satisfy (ADR-005).
///
/// Gates are measured separately so a new device or OS degrades honestly: a met hardware gate
/// says nothing about permission, and nothing a probe measures says a capability is verified.
public enum GateKind: String, CaseIterable, Sendable, Codable {
    /// The device has the sensor, radio, or chip the capability needs.
    case hardware
    /// The framework is compiled into this build and the running OS provides the API.
    case osAPI = "os-api"
    /// An on-device model or other downloadable asset is installed.
    case asset
    /// The person has allowed this app to use a protected resource.
    case permission
    /// The signed build carries what the system requires before it will grant access: Mac
    /// sandbox and hardened-runtime entitlements, and Info.plist purpose strings.
    case entitlement
    /// A system service or account-level setting is enabled and supports this configuration.
    case service
    /// Recorded device evidence exists. Probes never satisfy this gate.
    case verification

    public var title: String {
        switch self {
        case .hardware: "Hardware"
        case .osAPI: "OS and API"
        case .asset: "On-device asset"
        case .permission: "Permission"
        case .entitlement: "Entitlement"
        case .service: "Service"
        case .verification: "Verification"
        }
    }
}

/// What a probe measured for one gate.
public enum GateState: String, CaseIterable, Sendable, Codable {
    /// Measured and satisfied.
    case met
    /// Not satisfied yet, but an explicit feature action can satisfy it, such as asking for
    /// permission or downloading an asset. Probes never take that action.
    case needsAction = "needs-action"
    /// The person declined permission.
    case denied
    /// Policy, such as device management or Screen Time, prevents access.
    case restricted
    /// Measured and not satisfied, and nothing inside the app can change that.
    case unmet
    /// Not measurable here, or not yet measured. Never treated as satisfied.
    case unknown
}

/// A gate with its measured state and a plain-language explanation of what was read.
public struct CapabilityGate: Sendable, Equatable, Identifiable {
    public var kind: GateKind
    public var state: GateState
    /// What was measured, or why it could not be. Names the SDK symbol where one was read.
    public var detail: String

    public var id: GateKind { kind }

    public init(_ kind: GateKind, _ state: GateState, _ detail: String) {
        self.kind = kind
        self.state = state
        self.detail = detail
    }

    /// The verification gate as every probe reports it: no recorded device evidence.
    public static let noDeviceEvidence = CapabilityGate(
        .verification, .unknown,
        "Probes report availability only. Device verification needs recorded evidence."
    )
}
