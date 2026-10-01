import Foundation

/// Symbols and availability read from the installed Xcode 27.0 (27A266a) SDKs on 2026-09-30.
/// The live types below are the compile probe: a host that builds this file has linked the
/// framework, and `LiveHapticCapabilities.read()` calls the capability API without starting a cue.
public enum HapticAPIProbe {
    public static let coreHaptics = "CHHapticEngine iOS 13.0, macOS 10.15, tvOS 14.0, unavailable on watchOS"
    public static let capability = "CHHapticEngine.capabilitiesForHardware().supportsHaptics"
    public static let controller = "GCController.haptics and GCDeviceHaptics.createEngine(withLocality:) iOS 14.0, macOS 11.0, tvOS 14.0"
    public static let watch = "WKInterfaceDevice.play(_:) watchOS 2.0; no CHHapticPattern on watchOS"
}

#if os(iOS) || os(macOS) || os(tvOS)
import CoreHaptics
import GameController

public enum LiveHapticCapabilities {
    /// Reads hardware and controller support. It does not create an engine and it does not play.
    public static func read() -> DeviceHapticCapabilities {
        let hardware = CHHapticEngine.capabilitiesForHardware()
        let controller = GCController.controllers().contains { $0.haptics != nil }
        let audio: Bool
        #if os(tvOS)
        audio = false
        #else
        audio = true
        #endif
        return DeviceHapticCapabilities(
            coreHaptics: hardware.supportsHaptics,
            controllerHaptics: controller,
            watchSystem: false,
            quietAudio: audio
        )
    }
}

public enum LiveTactileGrammar {
    public static func makeEngine() -> TactileGrammarEngine {
        #if os(tvOS)
        let actuators = CueActuators(
            coreHaptics: CoreHapticsCueActuator(),
            controller: ControllerCueActuator()
        )
        #else
        let actuators = CueActuators(
            coreHaptics: CoreHapticsCueActuator(),
            controller: ControllerCueActuator(),
            audio: QuietCueAudio()
        )
        #endif
        return TactileGrammarEngine(actuators: actuators, capabilities: { LiveHapticCapabilities.read() })
    }
}

actor CoreHapticsCueActuator: HapticActuator {
    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?

    func play(_ delivery: CueDelivery) async throws {
        let hardware = CHHapticEngine.capabilitiesForHardware()
        guard hardware.supportsHaptics else { throw CueActuatorError.unsupported }
        let engine = try CHHapticEngine()
        self.engine = engine
        try await engine.start()
        let events = try hapticEvents(delivery.events)
        let pattern = try CHHapticPattern(events: events, parameters: [])
        let player = try engine.makePlayer(with: pattern)
        self.player = player
        try player.start(atTime: CHHapticTimeImmediate)
    }

    func stop() async {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        if let engine {
            try? await engine.stop()
        }
        player = nil
        self.engine = nil
    }

    private func hapticEvents(_ events: [CueEvent]) throws -> [CHHapticEvent] {
        guard !events.isEmpty else { throw CueActuatorError.unsupported }
        return events.map { event in
            let parameters = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness),
            ]
            switch event.shape {
            case .transient:
                return CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: event.time)
            case .continuous:
                return CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: parameters,
                    relativeTime: event.time,
                    duration: event.duration
                )
            }
        }
    }
}

actor ControllerCueActuator: HapticActuator {
    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?

    func play(_ delivery: CueDelivery) async throws {
        guard let haptics = GCController.current?.haptics ?? GCController.controllers().first(where: { $0.haptics != nil })?.haptics else {
            throw CueActuatorError.unsupported
        }
        guard let engine = haptics.createEngine(withLocality: .default) else {
            throw CueActuatorError.unsupported
        }
        self.engine = engine
        try await engine.start()
        let events = delivery.events.map { event in
            let parameters = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness),
            ]
            return CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: event.time)
        }
        guard !events.isEmpty else { throw CueActuatorError.unsupported }
        let pattern = try CHHapticPattern(events: events, parameters: [])
        let player = try engine.makePlayer(with: pattern)
        self.player = player
        try player.start(atTime: CHHapticTimeImmediate)
    }

    func stop() async {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        if let engine {
            try? await engine.stop()
        }
        player = nil
        self.engine = nil
    }
}

#if os(tvOS)
// Apple TV has Core Haptics and GameController in the SDK. This host does not link the product,
// so this branch is only compiled if a later target does. Quiet audio stays off tvOS: AVFoundation
// is not a Companions tvOS link.
#else
import AVFoundation

actor QuietCueAudio: QuietAudioPlaying {
    private var player: AVAudioPlayer?

    func play(_ wav: Data) async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, options: [.mixWithOthers])
        try session.setActive(true)
        #endif
        let player = try AVAudioPlayer(data: wav)
        player.volume = 1
        self.player = player
        guard player.prepareToPlay(), player.play() else {
            throw CueActuatorError.failed("The quiet tone did not start.")
        }
    }

    func stop() async {
        player?.stop()
        player = nil
    }
}
#endif

#elseif os(watchOS)
import WatchKit

public enum LiveHapticCapabilities {
    public static func read() -> DeviceHapticCapabilities {
        DeviceHapticCapabilities(
            coreHaptics: false, controllerHaptics: false, watchSystem: true, quietAudio: false
        )
    }
}

public enum LiveTactileGrammar {
    public static func makeEngine() -> TactileGrammarEngine {
        TactileGrammarEngine(
            actuators: CueActuators(watch: WatchSystemCueActuator()),
            capabilities: { LiveHapticCapabilities.read() }
        )
    }
}

/// One system haptic per cue. `WKHapticType` has no custom waveform, and this actuator never
/// builds one. The delivery's event list is empty on this route.
actor WatchSystemCueActuator: HapticActuator {
    func play(_ delivery: CueDelivery) async throws {
        guard case .watchSystem(let haptic) = delivery.route else { throw CueActuatorError.unsupported }
        guard delivery.events.isEmpty else { throw CueActuatorError.unsupported }
        WKInterfaceDevice.current().play(Self.kind(haptic))
    }

    func stop() async {}

    private static func kind(_ haptic: SystemHaptic) -> WKHapticType {
        switch haptic {
        case .success: .success
        case .retry: .retry
        case .start: .start
        }
    }
}

#else

public enum LiveHapticCapabilities {
    public static func read() -> DeviceHapticCapabilities { .none }
}

public enum LiveTactileGrammar {
    public static func makeEngine() -> TactileGrammarEngine { TactileGrammarEngine() }
}

#endif
