import Foundation
import LabDomain
@testable import TactileGrammar
import Testing

@Suite struct CueOperationTests {
    @Test func threeCuesStayDistinguishable() {
        let patterns = CuePattern.all
        #expect(Set(patterns.map(\.spoken)).count == 3)
        #expect(Set(patterns.map(\.visual.word)).count == 3)
        #expect(Set(patterns.map(\.visual.pulseCount)).count == 2)
        #expect(Set(patterns.map(\.tone.frequencyHertz)).count == 3)
        #expect(Set(patterns.map(\.systemHaptic)).count == 3)
        #expect(patterns.map { $0.events.map(\.time) } != [patterns[0].events.map(\.time), patterns[0].events.map(\.time), patterns[0].events.map(\.time)])
    }

    @Test func originalTonesAreQuietWavs() {
        let standard = CuePattern.all.map { CueAudio.wav(for: $0.tone, amplitude: IntensityPreference.standard.audioAmplitude) }
        let quiet = CueAudio.wav(for: CuePattern.success.tone, amplitude: IntensityPreference.quiet.audioAmplitude)
        #expect(Set(standard).count == 3)
        for wav in standard {
            #expect(wav.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]))
            #expect(wav.count < 20_000)
            #expect(peak(wav) < Int(Float(Int16.max) * 0.2))
        }
        #expect(peak(quiet) < peak(standard[0]))
        #expect(CueAudio.wav(for: CuePattern.success.tone, amplitude: 0).isEmpty)
    }

    @Test func routerPrefersARealActuatorAndNeverAWatchWaveform() {
        let pattern = CuePattern.warning
        let muted = CueRouter.route(for: pattern, intensity: .muted, capabilities: .core)
        #expect(muted == .fallback)
        #expect(CueRouter.route(for: pattern, intensity: .standard, capabilities: .core) == .coreHaptics)
        #expect(CueRouter.route(for: pattern, intensity: .standard, capabilities: .controllerOnly) == .controller)
        let watch = CueRouter.route(for: pattern, intensity: .standard, capabilities: .watchOnly)
        #expect(watch == .watchSystem(.retry))
        #expect(CueRouter.route(for: pattern, intensity: .standard, capabilities: .none) == .fallback)
    }

    @Test func anUnsupportedActuatorFallsBackWithoutFailingTheCue() async throws {
        let actuator = RecordingActuator(error: .unsupported)
        let engine = makeEngine(core: actuator, capabilities: .core)
        let receipt = try await engine.play(play("success"))
        #expect(receipt.outcome == .fellBack)
        #expect(receipt.route == .fallback)
        #expect(receipt.visual.word == "Success")
        #expect(receipt.spoken == "Success.")
        #expect(await actuator.deliveries.isEmpty)
    }

    @Test func missingActuatorsUseTheVisualPulseAndOptionalTone() async throws {
        let audio = RecordingAudio()
        let engine = TactileGrammarEngine(
            actuators: CueActuators(audio: audio),
            capabilities: { .audioOnly },
            clock: { 0 }
        )
        let receipt = try await engine.play(play("timing"))
        #expect(receipt.route == .fallback)
        #expect(receipt.outcome == .delivered)
        #expect(receipt.audioPlayed)
        #expect(receipt.visual.pulseCount == 3)
        #expect(await audio.plays == 1)

        let silent = TactileGrammarEngine(capabilities: { .none }, clock: { 0 })
        let visual = try await silent.play(play("timing", id: RequestID()))
        #expect(visual.route == .fallback)
        #expect(!visual.audioPlayed)
        #expect(visual.spoken == CuePattern.timing.spoken)
    }

    @Test func mutedHapticsLeaveTheCueUsable() async throws {
        let actuator = RecordingActuator()
        let audio = RecordingAudio()
        let engine = TactileGrammarEngine(
            actuators: CueActuators(coreHaptics: actuator, audio: audio),
            capabilities: { .core },
            clock: { 0 }
        )
        let receipt = try await engine.play(play("warning", intensity: .muted))
        #expect(receipt.intensity == .muted)
        #expect(receipt.route == .fallback)
        #expect(receipt.visual.word == "Warning")
        #expect(receipt.spoken.contains("Warning"))
        #expect(!receipt.audioPlayed)
        #expect(await actuator.deliveries.isEmpty)
        #expect(await audio.plays == 0)
    }

    @Test func repeatedCuesObeyRateAndFatigueLimits() async throws {
        let actuator = RecordingActuator()
        let clock = ManualCueClock()
        let engine = makeEngine(core: actuator, capabilities: .core, clock: clock)
        let first = try await engine.play(play("success"))
        #expect(first.outcome == .delivered)
        #expect(first.route == .coreHaptics)
        let held = try await engine.play(play("success"))
        #expect(held.outcome == .limited(.rate))
        #expect(held.visual.word == "Success")
        #expect(await actuator.deliveries.count == 1)

        clock.milliseconds = CuePattern.success.minimumGapMilliseconds
        for index in 0..<4 {
            clock.milliseconds = CuePattern.success.minimumGapMilliseconds * (index + 1)
            let receipt = try await engine.play(play("success"))
            #expect(receipt.outcome == .delivered)
        }
        clock.milliseconds += CuePattern.success.minimumGapMilliseconds
        let tired = try await engine.play(play("success"))
        #expect(tired.outcome == .limited(.fatigue))
        #expect(tired.spoken == "Success.")
        #expect(await actuator.deliveries.count == CueLimits.fatigueCount)
    }

    @Test func aWatchRouteCarriesNoCustomEvents() async throws {
        let watch = RecordingActuator()
        let engine = TactileGrammarEngine(
            actuators: CueActuators(watch: watch),
            capabilities: { .watchOnly },
            clock: { 0 }
        )
        let receipt = try await engine.play(play("success"))
        #expect(receipt.route == .watchSystem(.success))
        let delivery = try #require(await watch.deliveries.first)
        #expect(delivery.events.isEmpty)
        #expect(delivery.route == .watchSystem(.success))
    }

    @Test func quietIntensityScalesTheHapticAndNotTheWords() async throws {
        let actuator = RecordingActuator()
        let engine = makeEngine(core: actuator, capabilities: .core)
        let receipt = try await engine.play(play("success", intensity: .quiet))
        #expect(receipt.spoken == CuePattern.success.spoken)
        let delivery = try #require(await actuator.deliveries.first)
        let expected = CuePattern.success.events[0].intensity * IntensityPreference.quiet.hapticScale
        #expect(delivery.events[0].intensity == expected)
    }

    @Test func invalidInputCommitsNothing() async throws {
        let actuator = RecordingActuator()
        let engine = makeEngine(core: actuator, capabilities: .core)
        await #expect(throws: CueError.invalidPattern("")) {
            try await engine.play(play(""))
        }
        await #expect(throws: CueError.invalidPattern("nope")) {
            try await engine.play(play("nope"))
        }
        #expect(await engine.receiptCount() == 0)
        #expect(await actuator.deliveries.isEmpty)
    }

    @Test func authorizationMatchesTheAdapterCeilingAndARetryReplays() async throws {
        let actuator = RecordingActuator()
        let engine = makeEngine(core: actuator, capabilities: .core)
        let id = RequestID()
        let receipt = try await engine.play(play("success", id: id, actor: .appUI))
        #expect(receipt.adapter == .appUI)
        let replay = try await engine.play(play("success", id: id, actor: .appUI))
        #expect(replay == receipt)
        #expect(await actuator.deliveries.count == 1)

        let intent = try await engine.play(play("warning", actor: .appIntent))
        #expect(intent.adapter == .appIntent)

        await #expect(throws: CueError.requestIDReused(id)) {
            try await engine.play(play("warning", id: id, actor: .appUI))
        }
        await #expect(throws: CueError.unauthorized(AuthorizationDenial(
            adapter: .modelTool, required: .commit, reason: .outsideAdapterCeiling
        ))) {
            try await engine.play(play("success", actor: .modelTool))
        }
        let proposal = try await engine.propose(patternID: "timing", as: .modelTool)
        #expect(proposal.summary == "Proposed the timing cue. Nothing was played.")
        await #expect(throws: CueError.unauthorized(AuthorizationDenial(
            adapter: .shareExtension, required: .commit, reason: .deniedByPolicy
        ))) {
            try await engine.play(play("success", actor: .share))
        }
        await #expect(throws: CueError.unauthorized(AuthorizationDenial(
            adapter: .appUI, required: .commit, reason: .notGranted
        ))) {
            try await engine.play(play("success", actor: .ungranted))
        }
        #expect(await actuator.deliveries.count == 2)
    }

    @Test func aPolicyCanRefuseAnOtherwiseAllowedPlay() async {
        let engine = TactileGrammarEngine(
            capabilities: { .none },
            clock: { 0 },
            denies: { _, _ in true }
        )
        await #expect(throws: CueError.unauthorized(AuthorizationDenial(
            adapter: .appUI, required: .commit, reason: .deniedByPolicy
        ))) {
            try await engine.play(play("success"))
        }
    }

    @Test func stoppingCancelsACueBeforeItIsRecorded() async throws {
        let actuator = GateActuator()
        let engine = makeEngine(core: actuator, capabilities: .core)
        let task = Task { try await engine.play(play("success")) }
        await actuator.waitUntilPlaying()
        let stopped = await engine.stop()
        #expect(stopped.sentence.hasPrefix("Stopped."))
        await #expect(throws: CueError.cancelled) { try await task.value }
        #expect(await engine.receiptCount() == 0)
    }

    @Test func resetDemoClearsOnlyThisExperimentsCueLog() async throws {
        let engine = makeEngine(core: RecordingActuator(), capabilities: .core)
        let other = makeEngine(core: RecordingActuator(), capabilities: .core)
        _ = try await engine.play(play("success"))
        _ = try await other.play(play("warning"))
        let reset = await engine.resetDemo()
        #expect(reset.clearedReceipts == 1)
        #expect(reset.sentence.contains("Lab data was not changed."))
        #expect(await engine.receiptCount() == 0)
        #expect(await other.receiptCount() == 1)
        let again = try await engine.play(play("success"))
        #expect(again.outcome == .delivered)
    }

    /// LAB-030-B: replay every cue from a clean log, without an actuator or audio device.
    @Test func aCleanReplayKeepsAllThreeMutedAndUnavailableCuesUsable() async throws {
        for intensity in [IntensityPreference.standard, .muted] {
            let engine = TactileGrammarEngine(capabilities: { .none }, clock: { 0 })
            for pattern in CuePattern.all {
                let request = play(pattern.id, intensity: intensity)
                let receipt = try await engine.play(request)
                #expect(receipt.route == .fallback)
                #expect(receipt.outcome == .delivered)
                #expect(receipt.visual == pattern.visual)
                #expect(receipt.spoken == pattern.spoken)
                #expect(!receipt.audioPlayed)
                #expect(try await engine.play(request) == receipt)
            }
            #expect(await engine.receiptCount() == 3)
            #expect(await engine.resetDemo().clearedReceipts == 3)
            #expect(await engine.receiptCount() == 0)
        }
    }

    @Test(arguments: CuePattern.all)
    func eachCueAdmitsAtItsExactRateBoundary(_ pattern: CuePattern) async throws {
        let clock = ManualCueClock()
        let actuator = RecordingActuator()
        let engine = makeEngine(core: actuator, capabilities: .core, clock: clock)
        _ = try await engine.play(play(pattern.id))
        clock.milliseconds = pattern.minimumGapMilliseconds - 1
        #expect(try await engine.play(play(pattern.id)).outcome == .limited(.rate))
        clock.milliseconds += 1
        #expect(try await engine.play(play(pattern.id)).outcome == .delivered)
        #expect(await actuator.deliveries.count == 2)
    }

    @Test func fatigueExpiresAtTheWindowBoundaryAndMutedCuesDoNotConsumeIt() async throws {
        let clock = ManualCueClock()
        let actuator = RecordingActuator()
        let engine = makeEngine(core: actuator, capabilities: .core, clock: clock)
        for index in 0..<CueLimits.fatigueCount {
            clock.milliseconds = index * CuePattern.success.minimumGapMilliseconds
            _ = try await engine.play(play("success"))
        }
        for pattern in CuePattern.all {
            #expect(try await engine.play(play(pattern.id, intensity: .muted)).outcome == .delivered)
        }
        clock.milliseconds = CueLimits.fatigueWindowMilliseconds - 1
        #expect(try await engine.play(play("warning")).outcome == .limited(.fatigue))
        clock.milliseconds += 1
        #expect(try await engine.play(play("warning")).outcome == .delivered)
        #expect(await actuator.deliveries.count == 6)
    }

    /// The live capability read and muted route run on the Mac. No output device is started.
    @Test func theInstalledMacAdapterCompletesEveryMutedCue() async throws {
        let capabilities = LiveHapticCapabilities.read()
        print("LAB-030-B capabilities: \(capabilities.sentence)")
        let engine = LiveTactileGrammar.makeEngine()
        for pattern in CuePattern.all {
            let receipt = try await engine.play(play(pattern.id, intensity: .muted))
            #expect(receipt.route == .fallback)
            #expect(receipt.spoken == pattern.spoken)
            #expect(receipt.visual == pattern.visual)
            #expect(!receipt.audioPlayed)
        }
        _ = await engine.stop()
        #expect(await engine.resetDemo().clearedReceipts == 3)
    }

    @Test func readingInstalledCapabilitiesDoesNotCrash() {
        let capabilities = LiveHapticCapabilities.read()
        #expect(!capabilities.sentence.isEmpty)
        #expect(HapticAPIProbe.watch.contains("watchOS 2.0"))
    }
}

private extension ActorScope {
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    static let appIntent = ActorScope(adapter: .appIntent, grants: Set(Permission.allCases))
    static let modelTool = ActorScope(adapter: .modelTool, grants: [.read, .propose])
    static let share = ActorScope(adapter: .shareExtension, grants: [.read, .propose, .commit])
    static let ungranted = ActorScope(adapter: .appUI, grants: [])
}

private extension DeviceHapticCapabilities {
    static let core = DeviceHapticCapabilities(
        coreHaptics: true, controllerHaptics: false, watchSystem: false, quietAudio: false
    )
    static let controllerOnly = DeviceHapticCapabilities(
        coreHaptics: false, controllerHaptics: true, watchSystem: false, quietAudio: false
    )
    static let watchOnly = DeviceHapticCapabilities(
        coreHaptics: false, controllerHaptics: false, watchSystem: true, quietAudio: false
    )
    static let audioOnly = DeviceHapticCapabilities(
        coreHaptics: false, controllerHaptics: false, watchSystem: false, quietAudio: true
    )
}

private final class ManualCueClock: @unchecked Sendable {
    var milliseconds = 0
    func now() -> Int { milliseconds }
}

private func makeEngine(
    core: any HapticActuator,
    capabilities: DeviceHapticCapabilities,
    clock: ManualCueClock = ManualCueClock()
) -> TactileGrammarEngine {
    TactileGrammarEngine(
        actuators: CueActuators(coreHaptics: core),
        capabilities: { capabilities },
        clock: { clock.milliseconds }
    )
}

private func play(
    _ patternID: String,
    id: RequestID = RequestID(),
    actor: ActorScope = .appUI,
    intensity: IntensityPreference = .standard
) -> CuePlay {
    CuePlay(id: id, actor: actor, patternID: patternID, intensity: intensity)
}

private func peak(_ wav: Data) -> Int {
    var highest = 0
    var offset = 44
    while offset + 1 < wav.count {
        let sample = Int(Int16(bitPattern: UInt16(wav[offset]) | UInt16(wav[offset + 1]) << 8))
        highest = max(highest, abs(sample))
        offset += 2
    }
    return highest
}

private actor RecordingActuator: HapticActuator {
    var deliveries: [CueDelivery] = []
    private let error: CueActuatorError?

    init(error: CueActuatorError? = nil) { self.error = error }

    func play(_ delivery: CueDelivery) async throws {
        if let error { throw error }
        deliveries.append(delivery)
    }
    func stop() async {}
}

private actor RecordingAudio: QuietAudioPlaying {
    var plays = 0
    func play(_ wav: Data) async throws { plays += 1 }
    func stop() async {}
}

private actor GateActuator: HapticActuator {
    private var isPlaying = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Error>?

    func waitUntilPlaying() async {
        if isPlaying { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func play(_ delivery: CueDelivery) async throws {
        isPlaying = true
        waiter?.resume()
        waiter = nil
        try await withCheckedThrowingContinuation { release = $0 }
    }

    func stop() async {
        release?.resume(throwing: CancellationError())
        release = nil
    }
}
