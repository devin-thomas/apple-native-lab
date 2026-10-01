import Foundation

/// LAB-030. The three cues are original patterns owned by the lab. They are not Apple's haptic
/// symbols, and a Watch never receives their event list: Watch plays one system haptic instead.
public enum CueKind: String, Hashable, Sendable, CaseIterable, Codable {
    case success
    case warning
    case timing

    public var title: String {
        switch self {
        case .success: "Success"
        case .warning: "Warning"
        case .timing: "Timing"
        }
    }
}

/// One moment in a cue. Times are seconds from the start. Intensity and sharpness are 0...1
/// before the person's intensity preference scales them.
public struct CueEvent: Hashable, Sendable, Codable {
    public enum Shape: String, Hashable, Sendable, Codable {
        case transient
        case continuous
    }

    public let shape: Shape
    public let time: Double
    public let duration: Double
    public let intensity: Float
    public let sharpness: Float

    public init(shape: Shape, time: Double, duration: Double, intensity: Float, sharpness: Float) {
        self.shape = shape
        self.time = time
        self.duration = duration
        self.intensity = intensity
        self.sharpness = sharpness
    }

    public func scaled(by factor: Float) -> CueEvent {
        CueEvent(
            shape: shape,
            time: time,
            duration: duration,
            intensity: intensity * factor,
            sharpness: sharpness
        )
    }
}

/// What the screen shows for a cue. The word is always present, so the pulse is never color or
/// motion alone.
public struct VisualPulse: Hashable, Sendable, Codable {
    public let word: String
    public let symbol: String
    public let pulseCount: Int
    public let intervalMilliseconds: Int

    public init(word: String, symbol: String, pulseCount: Int, intervalMilliseconds: Int) {
        self.word = word
        self.symbol = symbol
        self.pulseCount = pulseCount
        self.intervalMilliseconds = intervalMilliseconds
    }
}

/// The original tone baked into a cue. Playback synthesizes it; nothing here is a recording.
public struct CueTone: Hashable, Sendable, Codable {
    public let frequencyHertz: Double
    public let pulses: Int
    public let pulseMilliseconds: Int
    public let gapMilliseconds: Int

    public init(frequencyHertz: Double, pulses: Int, pulseMilliseconds: Int, gapMilliseconds: Int) {
        self.frequencyHertz = frequencyHertz
        self.pulses = pulses
        self.pulseMilliseconds = pulseMilliseconds
        self.gapMilliseconds = gapMilliseconds
    }
}

/// A Watch plays one of these system haptics. They are names for `WKHapticType` cases the lab
/// uses, not a custom waveform and not the cue's event list.
public enum SystemHaptic: String, Hashable, Sendable, Codable {
    case success
    case retry
    case start
}

/// How strongly a cue is played. Muted still completes the cue: the visual pulse and the spoken
/// words remain, and no haptic or tone is started.
public enum IntensityPreference: String, Hashable, Sendable, Codable, CaseIterable {
    case muted
    case quiet
    case standard

    public var title: String {
        switch self {
        case .muted: "Muted"
        case .quiet: "Quiet"
        case .standard: "Standard"
        }
    }

    /// Scale applied to haptic event intensity. Muted is zero because no haptic is started.
    public var hapticScale: Float {
        switch self {
        case .muted: 0
        case .quiet: 0.35
        case .standard: 1
        }
    }

    /// Peak fraction of full scale for the synthesized tone. Both audible steps stay quiet.
    public var audioAmplitude: Float {
        switch self {
        case .muted: 0
        case .quiet: 0.04
        case .standard: 0.12
        }
    }
}

/// One distinguishable cue: a haptic event list, a visual pulse, spoken words, and a tone.
public struct CuePattern: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let kind: CueKind
    public let spoken: String
    public let visual: VisualPulse
    public let events: [CueEvent]
    public let tone: CueTone
    public let systemHaptic: SystemHaptic
    /// How long after a haptic play of this cue the next haptic play of it must wait.
    public let minimumGapMilliseconds: Int

    public var title: String { kind.title }

    public static let success = CuePattern(
        id: "success",
        kind: .success,
        spoken: "Success.",
        visual: VisualPulse(word: "Success", symbol: "checkmark.circle", pulseCount: 2, intervalMilliseconds: 120),
        events: [
            CueEvent(shape: .transient, time: 0, duration: 0, intensity: 0.7, sharpness: 0.85),
            CueEvent(shape: .transient, time: 0.09, duration: 0, intensity: 0.9, sharpness: 0.55),
        ],
        tone: CueTone(frequencyHertz: 988, pulses: 2, pulseMilliseconds: 40, gapMilliseconds: 50),
        systemHaptic: .success,
        minimumGapMilliseconds: 400
    )

    public static let warning = CuePattern(
        id: "warning",
        kind: .warning,
        spoken: "Warning. Something needs attention.",
        visual: VisualPulse(word: "Warning", symbol: "exclamationmark.triangle", pulseCount: 3, intervalMilliseconds: 160),
        events: [
            CueEvent(shape: .continuous, time: 0, duration: 0.18, intensity: 0.85, sharpness: 0.2),
            CueEvent(shape: .transient, time: 0.22, duration: 0, intensity: 0.6, sharpness: 0.35),
        ],
        tone: CueTone(frequencyHertz: 196, pulses: 2, pulseMilliseconds: 90, gapMilliseconds: 40),
        systemHaptic: .retry,
        minimumGapMilliseconds: 600
    )

    public static let timing = CuePattern(
        id: "timing",
        kind: .timing,
        spoken: "Timing. The beat is ready.",
        visual: VisualPulse(word: "Timing", symbol: "metronome", pulseCount: 3, intervalMilliseconds: 180),
        events: [
            CueEvent(shape: .transient, time: 0, duration: 0, intensity: 0.55, sharpness: 0.7),
            CueEvent(shape: .transient, time: 0.16, duration: 0, intensity: 0.55, sharpness: 0.7),
            CueEvent(shape: .transient, time: 0.32, duration: 0, intensity: 0.55, sharpness: 0.7),
        ],
        tone: CueTone(frequencyHertz: 440, pulses: 3, pulseMilliseconds: 30, gapMilliseconds: 130),
        systemHaptic: .start,
        minimumGapMilliseconds: 800
    )

    public static let all: [CuePattern] = [.success, .warning, .timing]

    public static func known(_ id: String) -> CuePattern? {
        all.first { $0.id == id }
    }

    public func events(scaledBy factor: Float) -> [CueEvent] {
        events.map { $0.scaled(by: factor) }
    }
}

/// How often haptic plays may repeat. The visual pulse is not counted: a cue the actuator will
/// not play still has to leave the task usable.
public enum CueLimits {
    public static let fatigueCount = 5
    public static let fatigueWindowMilliseconds = 10_000
}
