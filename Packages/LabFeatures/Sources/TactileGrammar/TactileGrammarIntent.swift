#if os(iOS) || os(macOS)
import AppIntents
import Foundation
import LabDomain

extension CueKind: AppEnum {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Cue")
    public static let caseDisplayRepresentations: [CueKind: DisplayRepresentation] = [
        .success: "Success",
        .warning: "Warning",
        .timing: "Timing",
    ]
}

/// Plays one cue through `TactileGrammarCenter`, the same engine the buttons use.
public struct PlayTactileCueIntent: AppIntent {
    public static let title: LocalizedStringResource = "Play Tactile Cue"
    public static let description = IntentDescription(
        "Plays a success, warning, or timing cue. The visual pulse and the spoken words always play. Haptics follow this device and the intensity setting."
    )
    public static let supportedModes: IntentModes = .foreground(.dynamic)

    @Parameter(title: "Cue")
    public var cue: CueKind

    public init() {
        cue = .success
    }

    public init(cue: CueKind) {
        self.cue = cue
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let pattern = CuePattern.all.first { $0.kind == cue } ?? .success
        let actor = ActorScope(adapter: .appIntent, grants: Set(Permission.allCases))
        let request = CuePlay(actor: actor, patternID: pattern.id, intensity: .standard)
        let receipt = try await TactileGrammarCenter.shared.play(request)
        return .result(dialog: "\(receipt.summary)")
    }
}

public struct TactileGrammarIntentsPackage: AppIntentsPackage {}
#endif
