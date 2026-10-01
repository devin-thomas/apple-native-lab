import Foundation

/// Where the graph's output goes right now.
public enum GraphOutput: Hashable, Sendable {
    /// Live playback through the system's current output.
    case live(OutputDescription)
    /// Nothing is playing; offline renders go to memory and an exported file.
    case offline
}

/// The live output's format, as the output reported it when it last started.
public struct OutputDescription: Hashable, Sendable {
    public let sampleRate: Double
    public let channels: Int
    /// The system's name for the route, such as "Speaker", or a plain description when the
    /// platform gives none without further permission.
    public let route: String

    public init(sampleRate: Double, channels: Int, route: String) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.route = route
    }

    public var summary: String { "\(route), \(Int(sampleRate)) Hz, \(channels == 1 ? "mono" : "stereo")" }
}

/// One stage of the graph, as the workshop shows and speaks it.
public struct GraphNode: Identifiable, Hashable, Sendable {
    public enum Role: String, Hashable, Sendable {
        case source, filter, gain, bypass, mute, limiter, output
    }

    public let role: Role
    public let title: String
    /// The node's settings in one line.
    public let detail: String
    /// Whether the node is shaping the sound right now. A bypassed or disabled stage is inactive.
    public let isActive: Bool

    public var id: Role { role }

    /// What VoiceOver says for the node.
    public var spokenSummary: String { "\(title), \(isActive ? "active" : "inactive"). \(detail)" }
}

/// The graph as inspectable data: every stage in signal order, derived from the same preset and
/// session state the kernel runs with. The views draw it; nothing reads audio to build it.
public enum AudioGraph {
    public static func nodes(
        preset: AudioGraphPreset,
        bypassed: Bool,
        muted: Bool,
        output: GraphOutput
    ) -> [GraphNode] {
        let processing = !bypassed
        return [
            GraphNode(role: .source, title: "Original loop",
                      detail: "\(preset.loop.title). \(preset.loop.detail)", isActive: true),
            GraphNode(role: .filter, title: "Low-pass filter",
                      detail: preset.filterEnabled
                          ? "Cutoff \(AudioGraphPreset.hertzText(preset.cutoffHertz)), Q \(String(format: "%.1f", preset.resonance)). \(preset.midi.summary)."
                          : "Off. The signal passes unfiltered.",
                      isActive: processing && preset.filterEnabled),
            GraphNode(role: .gain, title: "Gain",
                      detail: "\(AudioGraphPreset.decibelText(preset.gainDecibels)), ramped over about 20 ms so it never jumps.",
                      isActive: processing),
            GraphNode(role: .bypass, title: "Bypass",
                      detail: bypassed ? "On: the loop plays unprocessed." : "Off: the filter and gain shape the loop.",
                      isActive: bypassed),
            GraphNode(role: .mute, title: "Panic mute",
                      detail: muted ? "Muted: the output fades to silence within a few milliseconds." : "Open.",
                      isActive: muted),
            GraphNode(role: .limiter, title: "Safety limit",
                      detail: "Holds every sample within full scale and counts any it limits.", isActive: true),
            GraphNode(role: .output, title: "Output", detail: outputDetail(output), isActive: true),
        ]
    }

    static func outputDetail(_ output: GraphOutput) -> String {
        switch output {
        case .live(let description): "Playing live: \(description.summary)."
        case .offline: "Not playing. Offline renders go to memory and a file you export."
        }
    }
}
