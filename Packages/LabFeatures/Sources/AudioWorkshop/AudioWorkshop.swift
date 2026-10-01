import Foundation
import LabDomain

/// LAB-029 Audio Workshop: a tiny audio processor. An original loop runs through a low-pass filter
/// and a gain stage, with bypass and panic mute always in reach and one MIDI controller mapped to
/// the cutoff. It plays live through AVAudioEngine, processes files offline when live output is
/// unavailable, and is also packaged as an AUv3 effect.
public enum AudioWorkshop {
    public static let experimentID = "LAB-029"
    public static let title = "Audio Workshop"
    public static let symbol = "slider.vertical.3"

    /// The collection that holds the person's saved presets. Its ID is fixed, so every save, on
    /// every launch, finds the same collection instead of adding another.
    public static let presetCollectionID = CollectionID(rawValue: UUID(uuidString: "76573EDC-03EC-43E3-B1EA-A1122CAA5CF6")!)
    public static let presetCollectionTitle = "Audio Workshop Presets"

    /// The sample rate of offline renders and of the audio unit before a host sets its own.
    public static let offlineSampleRate: Double = 48_000
}

/// One of the three original loops. Each is synthesized by the kernel from tones and seeded noise,
/// so no recording is bundled and every render of the same loop at the same rate is identical.
public enum LoopFixture: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case pulse
    case chords
    case noise

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pulse: "Pulse"
        case .chords: "Chords"
        case .noise: "Noise and Thump"
        }
    }

    public var detail: String {
        switch self {
        case .pulse: "Eight plucked sine notes, one every eighth note at 120 BPM."
        case .chords: "Four soft three-note chords, half a second each."
        case .noise: "Seeded noise bursts over a low sine thump. The filter is easiest to hear here."
        }
    }

    /// The kernel's loop parameter value.
    var kernelValue: Double {
        switch self {
        case .pulse: 0
        case .chords: 1
        case .noise: 2
        }
    }

    /// Every loop is two seconds: eight eighth notes at 120 BPM.
    public static let seconds: Double = 2
}

/// A parameter of the running graph. The ranges match the kernel's, which clamps every write.
public enum WorkshopParameter: String, Hashable, Sendable, CaseIterable {
    case gainDecibels
    case cutoffHertz
    case resonance
    case filterEnabled
    case bypass
    case mute
    case loop

    public var range: ClosedRange<Double> {
        switch self {
        case .gainDecibels: -60...6
        case .cutoffHertz: 20...20_000
        case .resonance: 0.5...8
        case .filterEnabled, .bypass, .mute: 0...1
        case .loop: 0...2
        }
    }
}
