import LabDomain
import TactileGrammar
import Testing

/// LAB-030-B in the iPhone host. Muted plays read the live capability API but never start audio
/// or an actuator. A simulator pass says nothing about physical haptic output.
@Suite struct TactileGrammarPhoneTests {
    @Test func everyMutedCueCompletesInsideTheApp() async throws {
        let engine = LiveTactileGrammar.makeEngine()
        let capabilities = await engine.currentCapabilities()
        print("LAB-030-B phone capabilities: \(capabilities.sentence)")
        for pattern in CuePattern.all {
            let request = CuePlay(
                actor: ActorScope(adapter: .appUI, grants: Set(Permission.allCases)),
                patternID: pattern.id, intensity: .muted
            )
            let receipt = try await engine.play(request)
            #expect(receipt.route == .fallback)
            #expect(receipt.outcome == .delivered)
            #expect(receipt.visual == pattern.visual)
            #expect(receipt.spoken == pattern.spoken)
            #expect(!receipt.audioPlayed)
            #expect(try await engine.play(request) == receipt)
        }
        #expect(await engine.receiptCount() == 3)
        _ = await engine.stop()
        #expect(await engine.resetDemo().clearedReceipts == 3)
        #expect(await engine.receiptCount() == 0)
    }
}
