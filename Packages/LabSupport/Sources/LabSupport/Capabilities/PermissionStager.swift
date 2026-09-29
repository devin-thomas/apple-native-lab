/// An explicit step a person takes inside an experiment that needs a capability, such as
/// "Start camera preview" in LAB-026. Permission requests require one, so launch, probes, and
/// the Readiness screen have no way to prompt.
public struct FeatureAction: Sendable, Hashable {
    public var capability: Capability
    /// The experiment that owns the action, such as "LAB-026".
    public var experimentID: String
    /// What the person chose to do, in their words.
    public var title: String

    public init(capability: Capability, experimentID: String, title: String) {
        self.capability = capability
        self.experimentID = experimentID
        self.title = title
    }
}

/// Shows the system permission prompt. Only `PermissionStager` holds one.
public protocol PermissionRequesting: Sendable {
    /// Asks the system and returns the resulting status. Called only for permissions that are
    /// directly requestable, not determined, and declared in Info.plist.
    func request(_ permission: PermissionKind) async -> PermissionStatus
}

/// What a feature should do after staging a permission.
public enum PermissionOutcome: Sendable, Equatable {
    /// The capability needs no permission.
    case notRequired
    /// Access is allowed. The feature may start its live adapter.
    case granted
    /// The system asks when the feature starts its session, such as a Bluetooth manager or an
    /// NISession. The feature starts it and takes the fallback if the system reports a denial.
    case systemAsksOnUse(ifDeclined: FallbackRoute)
    /// The live path is closed. The feature shows this documented alternate route.
    case fallback(FallbackRoute, reason: FallbackReason)

    public var fallbackRoute: FallbackRoute? {
        switch self {
        case .notRequired, .granted: nil
        case .systemAsksOnUse(let route): route
        case .fallback(let route, _): route
        }
    }
}

public enum FallbackReason: Sendable, Equatable {
    /// Declined earlier. The lab does not ask again or open Settings on its own.
    case denied
    /// Blocked by device policy.
    case restricted
    /// Declined at the prompt this action just showed.
    case declinedNow
    /// The build lacks the Info.plist purpose string, so asking would end the process.
    case missingPurposeString(String)
    /// The signed Mac build lacks an entitlement the sandbox or hardened runtime requires.
    case missingEntitlement(String)
    /// The status could not be read or was not recognized.
    case unknownStatus
}

/// Requests a permission only when a feature action explicitly calls for it.
///
/// Rules, in order:
/// 1. A capability without a permission needs nothing.
/// 2. A readable status that is allowed returns at once; denied or restricted routes to the
///    capability's fallback without asking again; an unrecognized status also falls back.
/// 3. A missing purpose string or required Mac entitlement falls back instead of asking,
///    because asking would end the process or fail silently.
/// 4. A permission the lab cannot ask for by itself returns `systemAsksOnUse`.
/// 5. Otherwise the system prompt is shown once. Concurrent requests share that one prompt.
public actor PermissionStager {
    private let platform: LabPlatform
    private let source: any CapabilitySource
    private let requester: any PermissionRequesting
    private var inFlight: [PermissionKind: Task<PermissionStatus, Never>] = [:]

    public init(
        platform: LabPlatform = .current,
        source: any CapabilitySource,
        requester: any PermissionRequesting
    ) {
        self.platform = platform
        self.source = source
        self.requester = requester
    }

    /// The stager backed by this device's frameworks.
    public static func live() -> PermissionStager {
        PermissionStager(source: LiveCapabilitySource(), requester: LivePermissionRequester())
    }

    public func request(for action: FeatureAction) async -> PermissionOutcome {
        let capability = action.capability
        guard let permission = capability.permission else { return .notRequired }
        let fallback = capability.fallback

        if permission.unreadableReason == nil {
            switch source.permissionStatus(permission) {
            case .authorized: return .granted
            case .denied: return .fallback(fallback, reason: .denied)
            case .restricted: return .fallback(fallback, reason: .restricted)
            case .notReadable, .unrecognized: return .fallback(fallback, reason: .unknownStatus)
            case .notDetermined: break
            }
        }

        if let key = permission.purposeStringKey, !source.declaresPurposeString(key) {
            return .fallback(fallback, reason: .missingPurposeString(key))
        }
        for key in capability.requiredEntitlements(on: platform) where source.entitlement(key) != .present {
            return .fallback(fallback, reason: .missingEntitlement(key))
        }

        guard permission.isDirectlyRequestable else {
            return .systemAsksOnUse(ifDeclined: fallback)
        }

        let status = await prompt(permission)
        return switch status {
        case .authorized: .granted
        case .denied, .notDetermined: .fallback(fallback, reason: .declinedNow)
        case .restricted: .fallback(fallback, reason: .restricted)
        case .notReadable, .unrecognized: .fallback(fallback, reason: .unknownStatus)
        }
    }

    private func prompt(_ permission: PermissionKind) async -> PermissionStatus {
        if let pending = inFlight[permission] {
            return await pending.value
        }
        let requester = requester
        let task = Task { await requester.request(permission) }
        inFlight[permission] = task
        let status = await task.value
        inFlight[permission] = nil
        return status
    }
}
