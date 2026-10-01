import Foundation

/// An actuator the router can call. Throwing means "this actuator cannot play", which the
/// operation turns into the visual fallback. It must not be a crash.
public protocol HapticActuator: Sendable {
    func play(_ delivery: CueDelivery) async throws
    func stop() async
}

/// Optional quiet audio beside a cue. A failure here also leaves the visual pulse in place.
public protocol QuietAudioPlaying: Sendable {
    func play(_ wav: Data) async throws
    func stop() async
}

public struct CueDelivery: Hashable, Sendable {
    public let pattern: CuePattern
    public let intensity: IntensityPreference
    public let route: CueRoute
    public let events: [CueEvent]

    public init(pattern: CuePattern, intensity: IntensityPreference, route: CueRoute, events: [CueEvent]) {
        self.pattern = pattern
        self.intensity = intensity
        self.route = route
        self.events = events
    }
}

public enum CueActuatorError: Error, Hashable, Sendable {
    case unsupported
    case failed(String)
}

/// The actuators a host installed. A missing one is the unavailable path, not a crash.
public struct CueActuators: Sendable {
    public var coreHaptics: (any HapticActuator)?
    public var controller: (any HapticActuator)?
    public var watch: (any HapticActuator)?
    public var audio: (any QuietAudioPlaying)?

    public init(
        coreHaptics: (any HapticActuator)? = nil,
        controller: (any HapticActuator)? = nil,
        watch: (any HapticActuator)? = nil,
        audio: (any QuietAudioPlaying)? = nil
    ) {
        self.coreHaptics = coreHaptics
        self.controller = controller
        self.watch = watch
        self.audio = audio
    }

    func actuator(for route: CueRoute) -> (any HapticActuator)? {
        switch route {
        case .coreHaptics: coreHaptics
        case .controller: controller
        case .watchSystem: watch
        case .fallback: nil
        }
    }

    func stopAll() async {
        await coreHaptics?.stop()
        await controller?.stop()
        await watch?.stop()
        await audio?.stop()
    }
}
