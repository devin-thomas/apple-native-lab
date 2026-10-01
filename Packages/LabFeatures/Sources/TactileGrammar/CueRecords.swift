import Foundation
import LabDomain

/// Why a play did not start an actuator. Nothing was recorded in any of these cases.
public enum CueError: Error, Hashable, Sendable {
    case invalidPattern(String)
    /// The same denial reasons as the operation service (ADR-011): the adapter ceiling, the
    /// actor's grants, then the experiment's own narrower rule.
    case unauthorized(AuthorizationDenial)
    case requestIDReused(RequestID)
    case cancelled
    case unavailable(String)

    public var message: String {
        switch self {
        case .invalidPattern(let id):
            "“\(id)” is not a cue. Nothing was played."
        case .unauthorized(let denial):
            switch denial.reason {
            case .outsideAdapterCeiling:
                "This entry point cannot play a cue. Nothing was played."
            case .notGranted:
                "This entry point was not allowed to play a cue. Nothing was played."
            case .deniedByPolicy:
                "Playing a cue is a separate action, and this entry point cannot take it. Nothing was played."
            }
        case .requestIDReused:
            "That request was already used for a different cue. Nothing new was played."
        case .cancelled:
            "Stopped. Nothing was played."
        case .unavailable(let reason):
            reason
        }
    }
}

public enum CueLimit: String, Hashable, Sendable, Codable {
    case rate
    case fatigue
}

public enum CueOutcome: Hashable, Sendable, Codable {
    /// The chosen route ran. For a fallback, that is the visual pulse, with quiet audio only when
    /// `audioPlayed` is true.
    case delivered
    /// The haptic was held. The visual pulse and the spoken words were still produced.
    case limited(CueLimit)
    /// The actuator was selected and then failed. The visual pulse replaced it.
    case fellBack
}

/// The immutable record of one admitted play. A retry of the same request returns this value.
/// Cue receipts stay in the experiment: a cue is not a lab entity, so it is not a store row.
public struct CueReceipt: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let requestID: RequestID
    public let adapter: AdapterKind
    public let patternID: String
    public let kind: CueKind
    public let intensity: IntensityPreference
    public let route: CueRoute
    public let outcome: CueOutcome
    public let spoken: String
    public let visual: VisualPulse
    public let audioPlayed: Bool
    public let summary: String

    public init(
        id: UUID,
        requestID: RequestID,
        adapter: AdapterKind,
        patternID: String,
        kind: CueKind,
        intensity: IntensityPreference,
        route: CueRoute,
        outcome: CueOutcome,
        spoken: String,
        visual: VisualPulse,
        audioPlayed: Bool,
        summary: String
    ) {
        self.id = id
        self.requestID = requestID
        self.adapter = adapter
        self.patternID = patternID
        self.kind = kind
        self.intensity = intensity
        self.route = route
        self.outcome = outcome
        self.spoken = spoken
        self.visual = visual
        self.audioPlayed = audioPlayed
        self.summary = summary
    }
}

/// What a model tool may receive. Proposing does not play, and it does not record a receipt.
public struct CueProposal: Hashable, Sendable {
    public let patternID: String
    public let spoken: String
    public let summary: String
}

/// One request to play a cue. The actor is assigned by the caller, never decoded from a payload.
public struct CuePlay: Hashable, Sendable {
    public let id: RequestID
    public let actor: ActorScope
    public let patternID: String
    public let intensity: IntensityPreference

    public init(id: RequestID = RequestID(), actor: ActorScope, patternID: String, intensity: IntensityPreference) {
        self.id = id
        self.actor = actor
        self.patternID = patternID
        self.intensity = intensity
    }
}

struct AdmittedCue: Hashable, Sendable {
    let adapter: AdapterKind
    let patternID: String
    let intensity: IntensityPreference

    init(_ play: CuePlay) {
        adapter = play.actor.adapter
        patternID = play.patternID
        intensity = play.intensity
    }
}

/// The experiment's extra rule, under the adapter ceiling. Playing is an explicit action from the
/// app or an App Intent. Arriving through a share extension, a peer, or a model tool does not
/// play. A model tool can still propose, because propose is inside its ceiling.
public enum CueAuthorization {
    public static func denies(_ actor: ActorScope, _ permission: Permission) -> Bool {
        guard permission == .commit else { return false }
        return actor.adapter != .appUI && actor.adapter != .appIntent
    }
}

/// What one stop did. Stop never starts a cue.
public struct CueStop: Hashable, Sendable {
    public let sentence: String
}

/// What Reset Demo removed. Only this experiment's cue log, rate window, and intensity. Lab
/// collections, items, and sessions are not touched, because this operation does not hold the store.
public struct CueReset: Hashable, Sendable {
    public let clearedReceipts: Int
    public let sentence: String
}
