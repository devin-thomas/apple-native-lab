import Foundation
import LabDomain
@testable import LocalConstellation
import PeerSession
import Testing

/// LAB-019: the live conductor and joiner, over the in-process `LoopbackNetwork`, advertise,
/// browse, pair, and rejoin exactly as they would on the local network.
@MainActor
@Suite(.serialized) struct LiveSessionTests {
    @Test func aJoinerFindsTheConductorPairsWithTheCodeAndRejoinsWithoutOne() async throws {
        let network = LoopbackNetwork()
        let conductor = LiveConductor(
            identity: LocalIdentity(name: "Studio Mac"), trust: InMemoryTrustStore(), network: network,
            backend: ServiceShowBackend.inMemory(), sheet: try CueSheet.bundled()
        )
        #expect(conductor.networkStatus == .stopped, "nothing is advertised before a person starts it")
        await conductor.start()
        try await until { await MainActor.run { conductor.networkStatus == .ready } }

        let phone = LiveJoiner(role: .controller, identity: LocalIdentity(name: "Pocket phone"), trust: InMemoryTrustStore(), network: network)
        await phone.startBrowsing()
        let found = try await eventually { await MainActor.run { phone.conductors.first } }
        #expect(found.name == "Studio Mac")

        await conductor.openPairing()
        let joining = Task { await phone.join(found) }
        let request = try await eventually { await MainActor.run { conductor.state?.pairingRequest } }
        _ = try await eventually { await MainActor.run { phone.state?.codePrompt } }
        await phone.submitCode(request.code.digits)
        await conductor.answerPairing(allow: true)
        await joining.value
        try await until { await MainActor.run { phone.state?.phase == .live } }

        await phone.send(.goTo(cue: 4))
        try await until { await MainActor.run { phone.state?.snapshot?.cueTitle == "Ember" } }

        // The conductor restarts; the phone rejoins without a code, in the new epoch.
        let firstEpoch = conductor.state?.epoch
        await conductor.stop()
        try await until { await MainActor.run { if case .disconnected = phone.state?.phase { true } else { false } } }
        await conductor.start()
        let again = try await eventually { await MainActor.run { phone.conductors.first } }
        await phone.join(again)
        try await until { await MainActor.run { phone.state?.phase == .live } }
        #expect(phone.state?.epoch != firstEpoch)
        #expect(phone.lastOutcome == "Rejoined Studio Mac without a code.")
        await phone.shutdown()
        await conductor.stop()
    }
}
