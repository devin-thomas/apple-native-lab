import CryptoKit
import Foundation
@testable import PeerSession
import Synchronization
import Testing

/// LAB-019: explicit pairing with a short code plus pinned identity, and the refusals that leave
/// an unpaired or mismatched peer with nothing.
@Suite struct HandshakeTests {
    let hostIdentity = LocalIdentity(name: "Studio Mac")
    let joinerIdentity = LocalIdentity(name: "Pocket phone")

    /// A host that allows exactly what `approve` says, with pairing open for `attempts`.
    func host(
        trust: InMemoryTrustStore,
        offer: ProtocolOffer = Tally.offer,
        roles: Set<PeerRole> = [.controller, .display],
        attempts: Int = 3,
        open: Bool = true,
        approve: @escaping @Sendable (PairingRequest) async -> Bool
    ) -> HostHandshake {
        let left = Mutex(attempts)
        return HostHandshake(
            configuration: .init(identity: hostIdentity, offer: offer, trust: trust, stepTimeout: .seconds(5)),
            admission: .init(
                acceptsRole: { roles.contains($0) },
                takePairingAttempt: {
                    guard open else { return .closed }
                    return left.withLock { count in
                        guard count > 0 else { return .exhausted }
                        count -= 1
                        return .allowed
                    }
                },
                approve: approve
            )
        )
    }

    func joiner(trust: InMemoryTrustStore, offer: ProtocolOffer = Tally.offer, role: PeerRole = .controller) -> JoinerHandshake {
        JoinerHandshake(identity: joinerIdentity, offer: offer, role: role, trust: trust, stepTimeout: .seconds(5))
    }

    /// Runs both sides. The host's person reads the code into `shownCode`; the joiner's person
    /// types `typed(code)`.
    func run(
        host: HostHandshake,
        joiner: JoinerHandshake,
        mode: @escaping @Sendable () -> JoinerHandshake.Mode,
        tap: (@Sendable (Data) -> Void)? = nil
    ) async -> (host: Result<EstablishedLink, HandshakeFailure>, joiner: Result<EstablishedLink, HandshakeFailure>) {
        let (joinerEnd, hostEnd) = LoopbackConnection.pair("phone", "mac", tap: tap)
        async let hostResult = Result { () async throws(HandshakeFailure) -> EstablishedLink in try await host.run(on: hostEnd) }
        async let joinerResult = Result { () async throws(HandshakeFailure) -> EstablishedLink in
            try await joiner.run(on: joinerEnd, mode: mode())
        }
        return (await hostResult, await joinerResult)
    }

    @Test func aMatchingCodeAndTheHostsAllowPinBothIdentities() async throws {
        let hostTrust = InMemoryTrustStore(), joinerTrust = InMemoryTrustStore()
        let codes = Mutex<[PairingCode]>([])
        let shownOnHost = Mutex<PairingCode?>(nil)
        let host = host(trust: hostTrust) { request in
            codes.withLock { $0.append(request.code) }
            shownOnHost.withLock { $0 = request.code }
            return true
        }
        let (hostResult, joinerResult) = await run(host: host, joiner: joiner(trust: joinerTrust)) {
            .pair(enterCode: { prompt in
                #expect(prompt.host.name == "Studio Mac")
                // The person reads the code off the host's screen.
                while shownOnHost.withLock({ $0 }) == nil { try? await Task.sleep(for: .milliseconds(2)) }
                return shownOnHost.withLock { $0 }
            })
        }
        let hostLink = try hostResult.get(), joinerLink = try joinerResult.get()
        #expect(hostLink.remote.id == joinerIdentity.id && joinerLink.remote.id == hostIdentity.id)
        #expect(hostLink.joinerRole == .controller && hostLink.version == 1 && hostLink.pairedNow)
        #expect(codes.withLock { $0.count } == 1)
        #expect(codes.withLock { $0[0].digits.count } == 6)
        #expect(await hostTrust.check(joinerIdentity.identity, role: .controller) != .unknown)
        #expect(await joinerTrust.check(hostIdentity.identity, role: .conductor) != .unknown)
        // Only the paired role is pinned.
        #expect(await hostTrust.check(joinerIdentity.identity, role: .display) == .roleNotPaired)
    }

    @Test func aWrongCodePinsNothingOnEitherSide() async throws {
        let hostTrust = InMemoryTrustStore(), joinerTrust = InMemoryTrustStore()
        let host = host(trust: hostTrust) { _ in
            // The person waits; the joiner's refusal cancels this prompt.
            try? await Task.sleep(for: .seconds(30))
            return !Task.isCancelled
        }
        let (hostResult, joinerResult) = await run(host: host, joiner: joiner(trust: joinerTrust)) {
            .pair(enterCode: { _ in PairingCode(typed: "999 999") })
        }
        // A one-in-a-million chance that 999999 is the real code; it is not worth a flaky guard.
        #expect(joinerResult.failure == .refusedLocally(.codeMismatch))
        #expect(hostResult.failure == .refused(.codeMismatch, theirOffer: Tally.offer))
        #expect(await hostTrust.all().isEmpty)
        #expect(await joinerTrust.all().isEmpty)
    }

    @Test func theHostsDenyRefusesThePairing() async throws {
        let hostTrust = InMemoryTrustStore(), joinerTrust = InMemoryTrustStore()
        let shown = Mutex<PairingCode?>(nil)
        let host = host(trust: hostTrust) { request in
            shown.withLock { $0 = request.code }
            return false
        }
        let (hostResult, joinerResult) = await run(host: host, joiner: joiner(trust: joinerTrust)) {
            .pair(enterCode: { _ in
                while shown.withLock({ $0 }) == nil { try? await Task.sleep(for: .milliseconds(2)) }
                return shown.withLock { $0 }
            })
        }
        #expect(hostResult.failure == .refusedLocally(.notApproved))
        #expect(joinerResult.failure == .refused(.notApproved, theirOffer: Tally.offer))
        #expect(await hostTrust.all().isEmpty)
        #expect(await joinerTrust.all().isEmpty)
    }

    @Test func pairingThatIsClosedOrSpentIsRefusedBeforeAnyChallenge() async throws {
        let closed = host(trust: InMemoryTrustStore(), open: false) { _ in true }
        let (_, closedResult) = await run(host: closed, joiner: joiner(trust: InMemoryTrustStore())) { .pair(enterCode: { _ in nil }) }
        #expect(closedResult.failure == .refused(.pairingClosed, theirOffer: Tally.offer))

        let spent = host(trust: InMemoryTrustStore(), attempts: 0) { _ in true }
        let (_, spentResult) = await run(host: spent, joiner: joiner(trust: InMemoryTrustStore())) { .pair(enterCode: { _ in nil }) }
        #expect(spentResult.failure == .refused(.tooManyAttempts, theirOffer: Tally.offer))
    }

    @Test func anUnpairedPeerThatTriesToResumeGetsOnlyARefusal() async throws {
        let frames = Mutex<[Data]>([])
        let host = host(trust: InMemoryTrustStore()) { _ in true }
        let (hostResult, joinerResult) = await run(
            host: host, joiner: joiner(trust: InMemoryTrustStore()), mode: { .resume(host: LocalIdentity(name: "x").id) },
            tap: { bytes in frames.withLock { $0.append(bytes) } }
        )
        #expect(hostResult.failure == .refusedLocally(.pairingRequired))
        #expect(joinerResult.failure == .refused(.pairingRequired, theirOffer: Tally.offer))
        // Two frames crossed: the joiner's hello and the host's refusal. Neither is sealed, and the
        // refusal carries a reason and the protocol offer, nothing about the host or its session.
        let sent = frames.withLock { $0 }
        #expect(sent.count == 2)
        #expect(sent.allSatisfy { $0[4] == FrameCodec.Kind.handshake.rawValue })
        let refusal = try JSONSerialization.jsonObject(with: sent[1].dropFirst(5)) as? [String: Any]
        let body = refusal?["body"] as? [String: Any]
        #expect(refusal?["type"] as? String == "refusal")
        #expect(Set(body?.keys.map { $0 } ?? []) == ["reason", "offer"])
    }

    @Test func aPinnedPeerResumesWithoutACodeAndAnImpostorHostIsRefused() async throws {
        let hostTrust = InMemoryTrustStore(), joinerTrust = InMemoryTrustStore()
        await hostTrust.pin(PinnedPeer(identity: joinerIdentity.identity, roles: [.controller], pinnedAt: .now))
        await joinerTrust.pin(PinnedPeer(identity: hostIdentity.identity, roles: [.conductor], pinnedAt: .now))
        let host = host(trust: hostTrust) { _ in
            Issue.record("A resume never asks the person")
            return false
        }
        let hostID = hostIdentity.id
        let (hostResult, joinerResult) = await run(host: host, joiner: joiner(trust: joinerTrust)) { .resume(host: hostID) }
        #expect(try hostResult.get().pairedNow == false)
        #expect(try joinerResult.get().remote.id == hostIdentity.id)

        // Another device answering at the same address, with a different key, is refused by the
        // joiner before it sends anything but its hello and signature-free refusal.
        let impostor = HostHandshake(
            configuration: .init(identity: LocalIdentity(name: "Studio Mac"), offer: Tally.offer, trust: hostTrust),
            admission: .init(acceptsRole: { _ in true }, takePairingAttempt: { .closed }, approve: { _ in true })
        )
        let (_, fooled) = await run(host: impostor, joiner: joiner(trust: joinerTrust)) { .resume(host: hostID) }
        #expect(fooled.failure == .refusedLocally(.identityMismatch))
    }

    @Test func protocolAndVersionMismatchesAreExplainedRefusals() async throws {
        let newer = host(trust: InMemoryTrustStore(), offer: ProtocolOffer(name: "native-lab.tally", versions: 2...3)) { _ in true }
        let (_, result) = await run(host: newer, joiner: joiner(trust: InMemoryTrustStore())) { .pair(enterCode: { _ in nil }) }
        let failure = try #require(result.failure)
        #expect(failure == .refused(.versionUnsupported, theirOffer: ProtocolOffer(name: "native-lab.tally", versions: 2...3)))
        #expect(failure.explanation.contains("versions 2–3"))

        let other = host(trust: InMemoryTrustStore(), offer: ProtocolOffer(name: "native-lab.other", versions: 1...1)) { _ in true }
        let (_, otherResult) = await run(host: other, joiner: joiner(trust: InMemoryTrustStore())) { .pair(enterCode: { _ in nil }) }
        #expect(otherResult.failure == .refused(.protocolMismatch, theirOffer: ProtocolOffer(name: "native-lab.other", versions: 1...1)))
    }

    @Test func aRoleTheHostDoesNotAcceptIsRefused() async throws {
        let host = host(trust: InMemoryTrustStore(), roles: [.display]) { _ in true }
        let (_, result) = await run(host: host, joiner: joiner(trust: InMemoryTrustStore(), role: .controller)) { .pair(enterCode: { _ in nil }) }
        #expect(result.failure == .refused(.roleUnavailable, theirOffer: Tally.offer))
    }

    @Test func aDeviceInTheMiddleCannotMakeBothSidesShowOneCode() async throws {
        // The attacker runs a host handshake with the real joiner and a joiner handshake with the
        // real host. Each side derives its code from its own transcript, so the codes differ.
        let codeAtHost = Mutex<PairingCode?>(nil)
        let codeAtJoiner = Mutex<PairingCode?>(nil)
        let realHost = host(trust: InMemoryTrustStore()) { request in
            codeAtHost.withLock { $0 = request.code }
            try? await Task.sleep(for: .milliseconds(200))
            return false
        }
        let attackerHost = HostHandshake(
            configuration: .init(identity: LocalIdentity(name: "Studio Mac"), offer: Tally.offer, trust: InMemoryTrustStore()),
            admission: .init(acceptsRole: { _ in true }, takePairingAttempt: { .allowed }, approve: { request in
                codeAtJoiner.withLock { $0 = request.code }
                return false
            })
        )
        let attackerJoiner = JoinerHandshake(identity: LocalIdentity(name: "Pocket phone"), offer: Tally.offer, role: .controller, trust: InMemoryTrustStore())
        let (toHost, hostEnd) = LoopbackConnection.pair("attacker", "mac")
        let (toAttacker, attackerEnd) = LoopbackConnection.pair("phone", "attacker")
        async let a: Result<EstablishedLink, HandshakeFailure> = Result { () async throws(HandshakeFailure) in try await realHost.run(on: hostEnd) }
        async let b: Result<EstablishedLink, HandshakeFailure> = Result { () async throws(HandshakeFailure) in
            try await attackerJoiner.run(on: toHost, mode: .pair(enterCode: { _ in nil }))
        }
        async let c: Result<EstablishedLink, HandshakeFailure> = Result { () async throws(HandshakeFailure) in try await attackerHost.run(on: attackerEnd) }
        async let d: Result<EstablishedLink, HandshakeFailure> = Result { () async throws(HandshakeFailure) in
            try await joiner(trust: InMemoryTrustStore()).run(on: toAttacker, mode: .pair(enterCode: { _ in
                while codeAtHost.withLock({ $0 }) == nil { try? await Task.sleep(for: .milliseconds(2)) }
                return codeAtHost.withLock { $0 }
            }))
        }
        _ = await (a, b, c, d)
        let hostCode = try #require(codeAtHost.withLock { $0 })
        let joinerSideCode = try #require(codeAtJoiner.withLock { $0 })
        #expect(hostCode != joinerSideCode)
        #expect(await d.failure == .refusedLocally(.codeMismatch))
    }

    @Test func aTamperedSealedFrameClosesTheLink() async throws {
        let hostTrust = InMemoryTrustStore(), joinerTrust = InMemoryTrustStore()
        await hostTrust.pin(PinnedPeer(identity: joinerIdentity.identity, roles: [.controller], pinnedAt: .now))
        await joinerTrust.pin(PinnedPeer(identity: hostIdentity.identity, roles: [.conductor], pinnedAt: .now))
        let (joinerEnd, hostEnd) = LoopbackConnection.pair("phone", "mac")
        let hostID = hostIdentity.id
        async let hostLink = host(trust: hostTrust) { _ in false }.run(on: hostEnd)
        async let joinerLink = joiner(trust: joinerTrust).run(on: joinerEnd, mode: .resume(host: hostID))
        let (h, j) = try await (hostLink, joinerLink)
        let receiver = PeerLink<Tally>(h, isHost: true, clock: ManualPeerClock())
        var sender = j.channel
        var frame = try sender.seal(Data(#"{"kind":"x"}"#.utf8))
        frame[frame.count - 1] ^= 0x01
        try await joinerEnd.send(frame)
        #expect(await receiver.receive() == nil)
        #expect(await receiver.rejections == [.unauthenticated])
        #expect(await receiver.isClosed)
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { failure } else { nil }
    }
}
