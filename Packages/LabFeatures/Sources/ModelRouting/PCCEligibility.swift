/// One eligibility gate for Private Cloud Compute, kept separate from on-device model availability.
public struct RouteGate: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable, CaseIterable, Codable {
        case policy
        /// `com.apple.developer.private-cloud-compute` on the signed build.
        case entitlement
        /// Small Business Program enrollment and download-threshold eligibility ([S07]).
        case program
        /// App Store, TestFlight, or ad hoc distribution permitted for PCC ([S07]).
        case distribution
        /// SDK `PrivateCloudComputeLanguageModel.availability`.
        case availability
        /// SDK `quotaUsage`.
        case quota
        case consent

        public var title: String {
            switch self {
            case .policy: "Policy"
            case .entitlement: "Entitlement"
            case .program: "Program eligibility"
            case .distribution: "Distribution"
            case .availability: "PCC availability"
            case .quota: "Quota"
            case .consent: "Consent"
            }
        }
    }

    public enum State: String, Hashable, Sendable, Codable {
        case open
        case closed
        case unknown
    }

    public var id: String { "\(kind.rawValue):\(state.rawValue)" }
    public let kind: Kind
    public let state: State
    /// Exact sentence naming what was read. Safe for the UI; never a prompt.
    public let detail: String

    public init(_ kind: Kind, _ state: State, _ detail: String) {
        self.kind = kind
        self.state = state
        self.detail = detail
    }

    public var isOpen: Bool { state == .open }
}

/// Private Cloud Compute eligibility, modeled separately from on-device model availability.
///
/// Program enrollment, entitlement, distribution, SDK availability, and quota are distinct
/// gates. A ready on-device model does not open PCC, and an open PCC availability reading does
/// not imply the account gates are met ([S07], [VERIFICATION_BOUNDARIES]).
public struct PCCEligibility: Hashable, Sendable {
    public let entitlement: RouteGate
    public let program: RouteGate
    public let distribution: RouteGate
    public let availability: RouteGate
    public let quota: RouteGate

    public init(
        entitlement: RouteGate,
        program: RouteGate,
        distribution: RouteGate,
        availability: RouteGate,
        quota: RouteGate
    ) {
        self.entitlement = entitlement
        self.program = program
        self.distribution = distribution
        self.availability = availability
        self.quota = quota
    }

    public var gates: [RouteGate] {
        [entitlement, program, distribution, availability, quota]
    }

    public var closedGates: [RouteGate] {
        gates.filter { $0.state == .closed }
    }

    /// Every static and runtime gate that must be open before a PCC request can be offered.
    public var isFullyOpen: Bool {
        gates.allSatisfy(\.isOpen)
    }

    /// Explained sentence for the first closed gate, or `nil` when fully open.
    public var explanation: String? {
        closedGates.first.map { "\($0.kind.title): \($0.detail)" }
    }

    /// CoreLocal default: no PCC entitlement, program, or distribution claim. Availability and
    /// quota come from a probe or fixture.
    public static func coreLocalDefault(
        availability: RouteGate = RouteGate(
            .availability, .unknown,
            "Private Cloud Compute availability was not measured in this build."
        ),
        quota: RouteGate = RouteGate(
            .quota, .unknown,
            "Private Cloud Compute quota was not measured in this build."
        )
    ) -> PCCEligibility {
        PCCEligibility(
            entitlement: RouteGate(
                .entitlement, .closed,
                "This CoreLocal build does not carry \(ModelRouting.pccEntitlement)."
            ),
            program: RouteGate(
                .program, .closed,
                "Small Business Program enrollment and download-threshold eligibility are not claimed for this source build."
            ),
            distribution: RouteGate(
                .distribution, .closed,
                "PCC is permitted for App Store, TestFlight, or ad hoc distribution after entitlement assignment; this CoreLocal source build makes no such claim."
            ),
            availability: availability,
            quota: quota
        )
    }
}

/// On-device model availability, kept apart from PCC eligibility.
public struct OnDeviceAvailability: Hashable, Sendable {
    public let isAvailable: Bool
    public let detail: String

    public init(isAvailable: Bool, detail: String) {
        self.isAvailable = isAvailable
        self.detail = detail
    }

    public static let unknown = OnDeviceAvailability(
        isAvailable: false,
        detail: "On-device model availability was not measured."
    )
}

/// Quota for Private Cloud Compute, without any paid-provider alternative.
public enum QuotaState: Hashable, Sendable {
    case belowLimit(approaching: Bool)
    case limitReached
    case unknown

    public var isExhausted: Bool {
        if case .limitReached = self { true } else { false }
    }

    public var gate: RouteGate {
        switch self {
        case .belowLimit(let approaching):
            RouteGate(
                .quota, .open,
                approaching
                    ? "Private Cloud Compute quota is below the limit and approaching it (quotaUsage)."
                    : "Private Cloud Compute quota is below the limit (quotaUsage)."
            )
        case .limitReached:
            RouteGate(
                .quota, .closed,
                "Private Cloud Compute quota is exhausted (quotaUsage.isLimitReached). Local fallback stays available; no paid provider is offered."
            )
        case .unknown:
            RouteGate(.quota, .unknown, "Private Cloud Compute quota was not measured.")
        }
    }
}
