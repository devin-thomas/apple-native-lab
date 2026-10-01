/// Where a resolved request would run. Lab-owned; not an Apple symbol.
public enum InferenceRoute: String, Hashable, Sendable, CaseIterable, Codable {
    /// Apple's on-device `SystemLanguageModel`.
    case onDevice = "on-device"
    /// Apple's Private Cloud Compute model, only after every gate and consent open.
    case privateCloudCompute = "private-cloud-compute"
    /// Deterministic local generation or a manual workflow. No third-party key.
    case localFallback = "local-fallback"

    public var title: String {
        switch self {
        case .onDevice: "On-device model"
        case .privateCloudCompute: "Private Cloud Compute"
        case .localFallback: "Local fallback"
        }
    }

    /// Whether choosing this route would send anything off this device.
    public var leavesDevice: Bool {
        switch self {
        case .onDevice, .localFallback: false
        case .privateCloudCompute: true
        }
    }
}

/// The policy that decides whether cloud is even considered. Default is local-only.
public enum RoutingPolicy: String, Hashable, Sendable, CaseIterable, Codable {
    /// Never consider Private Cloud Compute or any other off-device route.
    case localOnly = "local-only"
    /// Cloud may be offered when entitlement, eligibility, quota, and consent are open.
    case cloudAllowed = "cloud-allowed"

    public var title: String {
        switch self {
        case .localOnly: "Local only"
        case .cloudAllowed: "Cloud allowed"
        }
    }
}
