/// The four ways to finish the task, as the experiment describes them. Each ends in the same
/// restore through the operation service and the same receipt; only how a person reads the chart
/// and reaches the control differs.
public enum InteractionAlternative: String, Hashable, Sendable, CaseIterable, Identifiable {
    case visual
    case voiceOver
    case keyboard
    case audioGraph

    /// The host a description is written for.
    public enum Host: Hashable, Sendable {
        case mac
        case phone
    }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .visual: "By sight"
        case .voiceOver: "With VoiceOver"
        case .keyboard: "By keyboard"
        case .audioGraph: "By ear, with Audio Graph"
        }
    }

    public var symbol: String {
        switch self {
        case .visual: "eye"
        case .voiceOver: "speaker.wave.2"
        case .keyboard: "keyboard"
        case .audioGraph: "waveform"
        }
    }

    /// How to finish the task this way on `host`, in one or two sentences.
    public func steps(on host: Host) -> String {
        switch (self, host) {
        case (.visual, .mac):
            "Find the longest bar in the chart. In the list, select one of that collection's samples and choose Restore Sample."
        case (.visual, .phone):
            "Find the longest bar in the chart, then tap Restore beside one of that collection's samples."
        case (.voiceOver, .mac):
            "Each bar reads its collection and count. On the bar with the most, open the actions with VO-Command-Space and choose a Restore action."
        case (.voiceOver, .phone):
            "Each bar reads its collection and count. On the bar with the most, swipe up or down to a Restore action and double-tap. The Archived Samples rotor moves between samples."
        case (.keyboard, .mac):
            "Press Command-5, then Tab to the list of archived samples. Select a sample with the arrow keys and press Return to restore it. Option-Command-L shows its receipt."
        case (.keyboard, .phone):
            "With a hardware keyboard and Full Keyboard Access, move to a sample's Restore button and press Space."
        case (.audioGraph, .mac):
            "With VoiceOver on the chart, open its Audio Graph and play it. The highest tone is the collection with the most archived samples; restore one of its samples from that bar's actions."
        case (.audioGraph, .phone):
            "With VoiceOver on the chart, choose Audio Graph in the rotor, then Play Audio Graph. The highest tone is the collection with the most archived samples; restore one of its samples from that bar's actions."
        }
    }

    /// The declared fallback, which needs no chart, no speech, and no audio.
    public static let fallback =
        "The summary and the list of archived samples carry the same numbers as the chart, and every sample in the list has its own Restore control."
}
