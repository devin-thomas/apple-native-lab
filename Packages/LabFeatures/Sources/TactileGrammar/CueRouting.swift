import Foundation

/// What a host has actually reported. A product name is not a capability: each flag is set from
/// an API probe or, in tests, from a fixture. Controller haptics are separate from "a controller
/// is connected", because support differs by device.
public struct DeviceHapticCapabilities: Hashable, Sendable, Codable {
    public var coreHaptics: Bool
    public var controllerHaptics: Bool
    public var watchSystem: Bool
    public var quietAudio: Bool

    public init(coreHaptics: Bool, controllerHaptics: Bool, watchSystem: Bool, quietAudio: Bool) {
        self.coreHaptics = coreHaptics
        self.controllerHaptics = controllerHaptics
        self.watchSystem = watchSystem
        self.quietAudio = quietAudio
    }

    public static let none = DeviceHapticCapabilities(
        coreHaptics: false, controllerHaptics: false, watchSystem: false, quietAudio: false
    )

    public var sentence: String {
        var parts: [String] = []
        parts.append(coreHaptics ? "Core Haptics is available." : "Core Haptics is not available.")
        parts.append(controllerHaptics
            ? "A connected controller reports haptics."
            : "No connected controller reports haptics.")
        parts.append(watchSystem
            ? "Watch system haptics are available. Custom waveforms are not used."
            : "Watch system haptics are not available on this host.")
        parts.append(quietAudio ? "A quiet tone can play." : "Quiet audio is not available on this host.")
        return parts.joined(separator: " ")
    }
}

/// Where a cue was sent. `.fallback` is the visual pulse; quiet audio is recorded separately
/// because it is optional.
public enum CueRoute: Hashable, Sendable, Codable {
    case coreHaptics
    case controller
    case watchSystem(SystemHaptic)
    case fallback

    public var title: String {
        switch self {
        case .coreHaptics: "Core Haptics"
        case .controller: "Controller haptics"
        case .watchSystem(let haptic): "Watch system haptic \(haptic.rawValue)"
        case .fallback: "Visual pulse"
        }
    }

    var isWatch: Bool {
        if case .watchSystem = self { true } else { false }
    }
}

/// Chooses a route from reported capabilities. Muted haptics always take the visual path, so a
/// task never depends on an actuator. When only the Watch flag is set, the route is one system
/// haptic and the cue's event list is not the payload.
public enum CueRouter {
    public static func route(
        for pattern: CuePattern,
        intensity: IntensityPreference,
        capabilities: DeviceHapticCapabilities
    ) -> CueRoute {
        if intensity == .muted { return .fallback }
        if capabilities.watchSystem && !capabilities.coreHaptics && !capabilities.controllerHaptics {
            return .watchSystem(pattern.systemHaptic)
        }
        if capabilities.coreHaptics { return .coreHaptics }
        if capabilities.controllerHaptics { return .controller }
        if capabilities.watchSystem { return .watchSystem(pattern.systemHaptic) }
        return .fallback
    }
}
