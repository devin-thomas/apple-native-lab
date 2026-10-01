import Foundation
import LabDomain

private struct RecordedCue {
    let admitted: AdmittedCue
    let receipt: CueReceipt
}

/// Plays one cue through the same authorization rules as the operation service, then records an
/// immutable receipt for the request ID.
///
/// A cue is not a lab entity, so this does not write the operation store and does not take an
/// ADR-013 grant. The ceiling, the grants, and a narrower policy are still checked on every call,
/// including a retry. The app, an App Intent, and a model tool's proposal all come here.
public actor TactileGrammarEngine {
    private let actuators: CueActuators
    private let capabilities: @Sendable () -> DeviceHapticCapabilities
    private let clock: @Sendable () -> Int
    private let denies: @Sendable (ActorScope, Permission) -> Bool
    private let makeID: @Sendable () -> UUID

    private var records: [RequestID: RecordedCue] = [:]
    private var hapticPlays: [(kind: CueKind, at: Int)] = []
    private var generation = 0

    public init(
        actuators: CueActuators = CueActuators(),
        capabilities: @escaping @Sendable () -> DeviceHapticCapabilities = { .none },
        clock: @escaping @Sendable () -> Int = { CueClock.milliseconds },
        denies: @escaping @Sendable (ActorScope, Permission) -> Bool = CueAuthorization.denies,
        makeID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.actuators = actuators
        self.capabilities = capabilities
        self.clock = clock
        self.denies = denies
        self.makeID = makeID
    }

    public func currentCapabilities() -> DeviceHapticCapabilities { capabilities() }

    public func receiptCount() -> Int { records.count }

    /// Describes a cue without playing it and without recording a receipt.
    public func propose(patternID: String, as actor: ActorScope) throws(CueError) -> CueProposal {
        guard let pattern = CuePattern.known(patternID) else { throw .invalidPattern(patternID) }
        try authorize(.propose, actor: actor)
        return CueProposal(
            patternID: pattern.id,
            spoken: pattern.spoken,
            summary: "Proposed the \(pattern.title.lowercased()) cue. Nothing was played."
        )
    }

    public func play(_ request: CuePlay) async throws(CueError) -> CueReceipt {
        do {
            return try await playAdmitted(request)
        } catch let error as CueError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .unavailable("The cue could not be played. Nothing was played.")
        }
    }

    /// Stops every installed actuator and any play that has not recorded a receipt yet.
    public func stop() async -> CueStop {
        generation += 1
        await actuators.stopAll()
        return CueStop(sentence: "Stopped. No further cue will play from the one that was running.")
    }

    /// Drops only this engine's cue log and haptic history.
    public func resetDemo() -> CueReset {
        let cleared = records.count
        records.removeAll()
        hapticPlays.removeAll()
        generation += 1
        let sentence = cleared == 1
            ? "Cleared 1 cue receipt. Lab data was not changed."
            : "Cleared \(cleared) cue receipts. Lab data was not changed."
        return CueReset(clearedReceipts: cleared, sentence: sentence)
    }

    private func playAdmitted(_ request: CuePlay) async throws -> CueReceipt {
        guard let pattern = CuePattern.known(request.patternID) else {
            throw CueError.invalidPattern(request.patternID)
        }
        try authorize(.commit, actor: request.actor)
        let admitted = AdmittedCue(request)
        if let recorded = records[request.id] {
            guard recorded.admitted == admitted else { throw CueError.requestIDReused(request.id) }
            return recorded.receipt
        }
        try Task.checkCancellation()
        let started = generation
        let now = clock()
        let device = capabilities()
        let selected = CueRouter.route(for: pattern, intensity: request.intensity, capabilities: device)
        if let limit = hapticLimit(for: pattern, route: selected, now: now) {
            return try finish(
                request, pattern: pattern, route: .fallback, outcome: .limited(limit),
                audioPlayed: false, admitted: admitted, started: started
            )
        }
        let played = await deliver(pattern, intensity: request.intensity, route: selected, device: device, started: started)
        try Task.checkCancellation()
        guard generation == started else { throw CueError.cancelled }
        if played.firedHaptic {
            hapticPlays.append((pattern.kind, now))
        }
        return try finish(
            request, pattern: pattern, route: played.route, outcome: played.outcome,
            audioPlayed: played.audioPlayed, admitted: admitted, started: started
        )
    }

    private struct Delivery {
        var route: CueRoute
        var outcome: CueOutcome
        var audioPlayed: Bool
        var firedHaptic: Bool
    }

    private func deliver(
        _ pattern: CuePattern,
        intensity: IntensityPreference,
        route: CueRoute,
        device: DeviceHapticCapabilities,
        started: Int
    ) async -> Delivery {
        guard intensity != .muted, route != .fallback else {
            let audio = await playAudio(pattern, intensity: intensity, device: device, started: started)
            return Delivery(route: .fallback, outcome: .delivered, audioPlayed: audio, firedHaptic: false)
        }
        // A Watch plays one system haptic. The cue's event list is not the payload.
        let events = pattern.events(scaledBy: intensity.hapticScale)
        let payload = route.isWatch ? [] : events
        let delivery = CueDelivery(pattern: pattern, intensity: intensity, route: route, events: payload)
        guard let actuator = actuators.actuator(for: route) else {
            let audio = await playAudio(pattern, intensity: intensity, device: device, started: started)
            return Delivery(route: .fallback, outcome: .fellBack, audioPlayed: audio, firedHaptic: false)
        }
        do {
            try await actuator.play(delivery)
        } catch is CancellationError {
            return Delivery(route: route, outcome: .delivered, audioPlayed: false, firedHaptic: false)
        } catch {
            let audio = await playAudio(pattern, intensity: intensity, device: device, started: started)
            return Delivery(route: .fallback, outcome: .fellBack, audioPlayed: audio, firedHaptic: false)
        }
        guard generation == started else {
            return Delivery(route: route, outcome: .delivered, audioPlayed: false, firedHaptic: false)
        }
        let audio = await playAudio(pattern, intensity: intensity, device: device, started: started)
        return Delivery(route: route, outcome: .delivered, audioPlayed: audio, firedHaptic: true)
    }

    private func playAudio(
        _ pattern: CuePattern,
        intensity: IntensityPreference,
        device: DeviceHapticCapabilities,
        started: Int
    ) async -> Bool {
        guard intensity != .muted, device.quietAudio, generation == started else { return false }
        guard let audio = actuators.audio else { return false }
        let wav = CueAudio.wav(for: pattern.tone, amplitude: intensity.audioAmplitude)
        guard !wav.isEmpty else { return false }
        do {
            try await audio.play(wav)
            return generation == started
        } catch {
            return false
        }
    }

    private func finish(
        _ request: CuePlay,
        pattern: CuePattern,
        route: CueRoute,
        outcome: CueOutcome,
        audioPlayed: Bool,
        admitted: AdmittedCue,
        started: Int
    ) throws -> CueReceipt {
        guard generation == started else { throw CueError.cancelled }
        let receipt = CueReceipt(
            id: makeID(),
            requestID: request.id,
            adapter: request.actor.adapter,
            patternID: pattern.id,
            kind: pattern.kind,
            intensity: request.intensity,
            route: route,
            outcome: outcome,
            spoken: pattern.spoken,
            visual: pattern.visual,
            audioPlayed: audioPlayed,
            summary: CueSummary.sentence(
                kind: pattern.kind, route: route, outcome: outcome,
                spoken: pattern.spoken, audioPlayed: audioPlayed, intensity: request.intensity
            )
        )
        records[request.id] = RecordedCue(admitted: admitted, receipt: receipt)
        return receipt
    }

    /// A haptic route that would fire again too soon, or after too many recent haptic plays.
    /// A visual-only route is never limited.
    private func hapticLimit(for pattern: CuePattern, route: CueRoute, now: Int) -> CueLimit? {
        guard route != .fallback else { return nil }
        let recent = hapticPlays.filter { now - $0.at < CueLimits.fatigueWindowMilliseconds }
        if recent.count >= CueLimits.fatigueCount { return .fatigue }
        if let last = hapticPlays.last(where: { $0.kind == pattern.kind }) {
            if now - last.at < pattern.minimumGapMilliseconds { return .rate }
        }
        return nil
    }

    private func authorize(_ permission: Permission, actor: ActorScope) throws(CueError) {
        let reason: AuthorizationDenial.Reason? =
            if !actor.adapter.ceiling.contains(permission) { .outsideAdapterCeiling }
            else if !actor.grants.contains(permission) { .notGranted }
            else if denies(actor, permission) { .deniedByPolicy }
            else { nil }
        if let reason {
            throw CueError.unauthorized(AuthorizationDenial(adapter: actor.adapter, required: permission, reason: reason))
        }
    }
}

enum CueSummary {
    static func sentence(
        kind: CueKind,
        route: CueRoute,
        outcome: CueOutcome,
        spoken: String,
        audioPlayed: Bool,
        intensity: IntensityPreference
    ) -> String {
        let name = kind.title.lowercased()
        let words = "The words “\(spoken)” showed with the \(patternWord(kind))."
        switch outcome {
        case .limited(.rate):
            return "Held the \(name) haptic. It was repeated too soon. \(words)"
        case .limited(.fatigue):
            return "Held the \(name) haptic. Recent cues reached the fatigue limit. \(words)"
        case .fellBack:
            return "The \(name) haptic could not play, so the visual pulse was used. \(words)"
        case .delivered:
            break
        }
        if intensity == .muted {
            return "Showed the \(name) cue as a visual pulse. Haptics are muted, so the cue did not need them. \(words)"
        }
        switch route {
        case .fallback:
            if audioPlayed {
                return "Played the \(name) cue as a visual pulse and a quiet tone. \(words)"
            }
            return "Played the \(name) cue as a visual pulse. \(words)"
        case .coreHaptics, .controller, .watchSystem:
            let tone = audioPlayed ? " A quiet tone played with it." : ""
            return "Played the \(name) cue through \(route.title).\(tone) \(words)"
        }
    }

    private static func patternWord(_ kind: CueKind) -> String {
        switch kind {
        case .success: "success pulse"
        case .warning: "warning pulse"
        case .timing: "timing pulse"
        }
    }
}

public enum CueClock {
    public static var milliseconds: Int {
        let interval = ProcessInfo.processInfo.systemUptime
        return Int((interval * 1000).rounded())
    }
}

/// The process-wide engine the app UI and the App Intent share. The app installs the live
/// actuators before any scene is shown. Tests build their own engine and do not come here.
public final class TactileGrammarCenter: @unchecked Sendable {
    public static let shared = TactileGrammarCenter()

    private let lock = NSLock()
    private var engine: TactileGrammarEngine

    public init() {
        engine = TactileGrammarEngine()
    }

    public func install(_ engine: TactileGrammarEngine) {
        lock.lock()
        self.engine = engine
        lock.unlock()
    }

    public func play(_ request: CuePlay) async throws(CueError) -> CueReceipt {
        try await current.play(request)
    }

    public func propose(patternID: String, as actor: ActorScope) async throws(CueError) -> CueProposal {
        try await current.propose(patternID: patternID, as: actor)
    }

    public func stop() async -> CueStop {
        await current.stop()
    }

    public func resetDemo() async -> CueReset {
        await current.resetDemo()
    }

    public func capabilities() async -> DeviceHapticCapabilities {
        await current.currentCapabilities()
    }

    private var current: TactileGrammarEngine {
        lock.lock()
        defer { lock.unlock() }
        return engine
    }
}
