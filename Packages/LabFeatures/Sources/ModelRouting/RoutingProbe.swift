import Foundation
#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import FoundationModels
#endif

/// Readings the observatory needs from the installed SDK and the signed build.
///
/// PCC eligibility gates that Apple does not expose as symbols (program enrollment, distribution)
/// stay injectable. Entitlement presence is also injectable so CoreLocal tests do not need a
/// CloudOptional profile.
public struct RoutingProbeReading: Hashable, Sendable {
    public var onDevice: OnDeviceAvailability
    public var pccAvailability: RouteGate
    public var quota: QuotaState
    public var carriesPCCEntitlement: Bool

    public init(
        onDevice: OnDeviceAvailability,
        pccAvailability: RouteGate,
        quota: QuotaState,
        carriesPCCEntitlement: Bool
    ) {
        self.onDevice = onDevice
        self.pccAvailability = pccAvailability
        self.quota = quota
        self.carriesPCCEntitlement = carriesPCCEntitlement
    }
}

/// Reads on-device and PCC availability. Does not send a cloud request.
public enum RoutingProbe {
    /// Whether this platform's build compiles the Foundation Models path used here.
    public static var isCompiled: Bool {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        true
        #else
        false
        #endif
    }

    /// Live reading. Entitlement defaults to absent for CoreLocal.
    public static func live(carriesPCCEntitlement: Bool = false) -> RoutingProbeReading {
        RoutingProbeReading(
            onDevice: readOnDevice(),
            pccAvailability: readPCCAvailability(),
            quota: readQuota(),
            carriesPCCEntitlement: carriesPCCEntitlement
        )
    }

    /// Builds PCC eligibility from a probe reading plus the account gates CoreLocal cannot claim.
    public static func eligibility(
        from reading: RoutingProbeReading,
        programEligible: Bool = false,
        distributionPermitted: Bool = false
    ) -> PCCEligibility {
        let entitlement: RouteGate = reading.carriesPCCEntitlement
            ? RouteGate(
                .entitlement, .open,
                "This build declares \(ModelRouting.pccEntitlement)."
            )
            : RouteGate(
                .entitlement, .closed,
                "This CoreLocal build does not carry \(ModelRouting.pccEntitlement)."
            )
        let program: RouteGate = programEligible
            ? RouteGate(.program, .open, "Small Business Program enrollment and fewer than two million first-time App Store downloads are recorded for this build.")
            : RouteGate(
                .program, .closed,
                "Small Business Program enrollment and download-threshold eligibility are not claimed for this source build."
            )
        let distribution: RouteGate = distributionPermitted
            ? RouteGate(.distribution, .open, "Distribution is one Apple permits for PCC.")
            : RouteGate(
                .distribution, .closed,
                "PCC is permitted for App Store, TestFlight, or ad hoc distribution after entitlement assignment; this CoreLocal source build makes no such claim."
            )
        return PCCEligibility(
            entitlement: entitlement,
            program: program,
            distribution: distribution,
            availability: reading.pccAvailability,
            quota: reading.quota.gate
        )
    }

    private static func readOnDevice() -> OnDeviceAvailability {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            let localeOK = model.supportsLocale()
            return OnDeviceAvailability(
                isAvailable: localeOK,
                detail: localeOK
                    ? "SystemLanguageModel.default.availability is .available and supportsLocale() is true."
                    : "SystemLanguageModel.default.availability is .available, but supportsLocale() is false."
            )
        case .unavailable(.deviceNotEligible):
            return OnDeviceAvailability(
                isAvailable: false,
                detail: "SystemLanguageModel.default.availability reports .deviceNotEligible."
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            return OnDeviceAvailability(
                isAvailable: false,
                detail: "SystemLanguageModel.default.availability reports .appleIntelligenceNotEnabled."
            )
        case .unavailable(.modelNotReady):
            return OnDeviceAvailability(
                isAvailable: false,
                detail: "SystemLanguageModel.default.availability reports .modelNotReady."
            )
        case .unavailable(let reason):
            return OnDeviceAvailability(
                isAvailable: false,
                detail: "SystemLanguageModel.default.availability reports unavailable (\(String(describing: reason)))."
            )
        @unknown default:
            return OnDeviceAvailability(
                isAvailable: false,
                detail: "SystemLanguageModel.default.availability returned an unknown case."
            )
        }
        #else
        return OnDeviceAvailability(
            isAvailable: false,
            detail: "FoundationModels is not compiled for this platform."
        )
        #endif
    }

    private static func readPCCAvailability() -> RouteGate {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS)) && compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            switch model.availability {
            case .available:
                return RouteGate(
                    .availability, .open,
                    "PrivateCloudComputeLanguageModel.availability is .available."
                )
            case .unavailable(.deviceNotEligible):
                return RouteGate(
                    .availability, .closed,
                    "PrivateCloudComputeLanguageModel.availability reports .deviceNotEligible."
                )
            case .unavailable(.systemNotReady):
                return RouteGate(
                    .availability, .closed,
                    "PrivateCloudComputeLanguageModel.availability reports .systemNotReady."
                )
            case .unavailable(let reason):
                return RouteGate(
                    .availability, .closed,
                    "PrivateCloudComputeLanguageModel.availability reports unavailable (\(String(describing: reason)))."
                )
            @unknown default:
                return RouteGate(
                    .availability, .unknown,
                    "PrivateCloudComputeLanguageModel.availability returned an unknown case."
                )
            }
        }
        return RouteGate(
            .availability, .closed,
            "PrivateCloudComputeLanguageModel requires iOS/macOS 27.0."
        )
        #else
        return RouteGate(
            .availability, .unknown,
            "The PCC probe is not compiled for this platform or SDK; availability was not measured."
        )
        #endif
    }

    private static func readQuota() -> QuotaState {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS)) && compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            let usage = PrivateCloudComputeLanguageModel().quotaUsage
            if usage.isLimitReached { return .limitReached }
            switch usage.status {
            case .belowLimit(let below):
                return .belowLimit(approaching: below.isApproachingLimit)
            case .limitReached:
                return .limitReached
            @unknown default:
                return .unknown
            }
        }
        return .unknown
        #else
        return .unknown
        #endif
    }
}
