import Foundation
import LabDomain
import Observation

/// The screen state for one window. Every button calls the process-wide engine, which is also
/// what the App Intent calls.
@MainActor
@Observable
public final class TactileGrammarModel {
    public private(set) var summary: String
    public private(set) var spoken: String
    public private(set) var visual: VisualPulse?
    public private(set) var routeTitle: String
    public private(set) var capabilitySentence: String
    public var intensity: IntensityPreference
    public private(set) var isBusy = false

    private let actor: ActorScope

    public init(actor: ActorScope = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))) {
        self.actor = actor
        intensity = .standard
        summary = "Choose a cue. The words and the pulse always show, even when haptics are muted or missing."
        spoken = ""
        routeTitle = ""
        capabilitySentence = "Device feedback has not been read yet."
    }

    public func refreshCapabilities() async {
        let capabilities = await TactileGrammarCenter.shared.capabilities()
        capabilitySentence = capabilities.sentence
    }

    public func play(_ kind: CueKind) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let pattern = CuePattern.all.first { $0.kind == kind } ?? .success
        let request = CuePlay(actor: actor, patternID: pattern.id, intensity: intensity)
        do {
            let receipt = try await TactileGrammarCenter.shared.play(request)
            apply(receipt)
        } catch {
            summary = error.message
            spoken = ""
            visual = nil
            routeTitle = ""
        }
    }

    public func stop() async {
        let stopped = await TactileGrammarCenter.shared.stop()
        summary = stopped.sentence
        isBusy = false
    }

    public func resetDemo() async {
        let reset = await TactileGrammarCenter.shared.resetDemo()
        intensity = .standard
        summary = reset.sentence
        spoken = ""
        visual = nil
        routeTitle = ""
    }

    private func apply(_ receipt: CueReceipt) {
        summary = receipt.summary
        spoken = receipt.spoken
        visual = receipt.visual
        routeTitle = receipt.route.title
    }
}

public enum TactileGrammarExperiment {
    public static let id = "LAB-030"
    public static let title = "Tactile Grammar"
    public static let symbol = "waveform"
}
