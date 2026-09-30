import CryptoKit
import Foundation
@testable import PeerSession
import Testing

/// LAB-019: the frame format, the envelope's strict decoding, and the text rules for anything a
/// peer sends.
@Suite struct WireTests {
    func envelope(_ message: SessionMessage<Tally>, base: Int? = nil, sequence: UInt64 = 1) -> SessionEnvelope<Tally> {
        SessionEnvelope(
            protocolVersion: 1, sessionID: LiveSessionID(rawValue: UUID(uuidString: "5B5E1D0C-0000-4000-8000-000000000019")!),
            sessionEpoch: SessionEpoch(rawValue: 7), messageID: MessageID(rawValue: UUID(uuidString: "0B1E0000-0000-4000-8000-000000000001")!),
            senderPeerID: LocalIdentity(name: "a").id, role: .controller, sequence: sequence,
            sentAt: PeerInstant(nanoseconds: 12), baseRevision: base, message: message
        )
    }

    @Test func framesSurviveAnyChunkingAndOversizeIsRefusedBeforeBuffering() throws {
        let frames = [Data([1, 2, 3]), Data(repeating: 9, count: 1_000), Data([0x02])]
        let stream = try frames.map(FrameCodec.encode).reduce(Data(), +)
        for chunk in [1, 3, 7, 1_024] {
            var reader = FrameReader()
            var received: [Data] = []
            var index = stream.startIndex
            while index < stream.endIndex {
                let end = min(index + chunk, stream.endIndex)
                received += try reader.append(Data(stream[index..<end]))
                index = end
            }
            #expect(received == frames)
            #expect(reader.pendingByteCount == 0)
        }
        var reader = FrameReader()
        #expect(throws: FrameError.tooLarge(FrameCodec.maximumFrameBytes + 1)) {
            _ = try reader.append(Data([0x00, 0x01, 0x00, 0x01]))
        }
        #expect(throws: FrameError.self) { _ = try reader.append(Data([1])) }
        #expect(throws: FrameError.empty) { _ = try FrameCodec.encode(Data()) }
        #expect(throws: FrameError.tooLarge(FrameCodec.maximumFrameBytes + 1)) {
            _ = try FrameCodec.encode(Data(count: FrameCodec.maximumFrameBytes + 1))
        }
    }

    @Test func everyMessageKindRoundTripsExactly() throws {
        let messages: [(SessionMessage<Tally>, Int?)] = [
            (.command(IssuedCommand(command: .add(2), issuedAt: PeerInstant(nanoseconds: 9), issuedIn: SessionEpoch(rawValue: 7))), 3),
            (.command(IssuedCommand(command: .set(5), issuedAt: PeerInstant(nanoseconds: 9), issuedIn: nil)), 0),
            (.result(CommandResult(commandID: MessageID(), disposition: .stale, revision: 4, summary: "Nothing changed.")), nil),
            (.snapshot(SnapshotBody(revision: 4, state: Tally.Snapshot(value: 12))), nil),
            (.snapshotRequest(.sequenceGap), nil),
            (.sample(SampleBody(origin: LocalIdentity(name: "b").id, sample: Tally.Sample(level: 0.25), streamSequence: 3)), nil),
            (.clockPing(ClockProbe(originatedAt: PeerInstant(nanoseconds: -5), receivedAt: nil, answeredAt: nil)), nil),
            (.clockPong(ClockProbe(originatedAt: PeerInstant(nanoseconds: 1), receivedAt: PeerInstant(nanoseconds: 2), answeredAt: PeerInstant(nanoseconds: 3))), nil),
            (.goodbye(.leaving), nil),
        ]
        for (message, base) in messages {
            let original = envelope(message, base: base)
            let json = original.json
            let decoded = try SessionEnvelope<Tally>(json: json)
            #expect(decoded == original)
            #expect(decoded.json == json, "encoding is deterministic")
        }
    }

    @Test func unknownOrSmuggledFieldsAndBadValuesAreRefused() throws {
        let command = envelope(.command(IssuedCommand(command: .add(1), issuedAt: PeerInstant(nanoseconds: 1), issuedIn: nil)), base: 0)
        let good = try JSONSerialization.jsonObject(with: command.json) as! [String: Any]

        func refuses(_ edit: (inout [String: Any]) -> Void) -> Bool {
            var object = good
            edit(&object)
            let data = try! JSONSerialization.data(withJSONObject: object)
            return (try? SessionEnvelope<Tally>(json: data)) == nil
        }
        #expect(refuses { $0["grant"] = "commit" })
        #expect(refuses { object in
            var payload = object["payload"] as! [String: Any]
            payload["shell"] = "rm -rf /"
            object["payload"] = payload
        })
        #expect(refuses { object in
            var payload = object["payload"] as! [String: Any]
            payload["command"] = ["method": "deleteEverything"]
            object["payload"] = payload
        })
        #expect(refuses { object in
            var payload = object["payload"] as! [String: Any]
            payload["command"] = ["add": 11]
            object["payload"] = payload
        }, "outside the vocabulary's bounds")
        #expect(refuses { $0["baseRevision"] = nil }, "a command needs the revision its sender saw")
        #expect(refuses { $0["channel"] = "replaceable" }, "a command is reliable")
        #expect(refuses { $0["sequence"] = 0 })
        #expect(refuses { $0["role"] = "administrator" })
        #expect(refuses { $0["kind"] = "execute" })
        #expect(refuses { $0["senderPeerID"] = "ABC" })

        // Duplicate keys, which a plain decoder would silently merge, are refused.
        let text = String(decoding: command.json, as: UTF8.self)
        let duplicated = text.replacingOccurrences(of: "\"role\":\"controller\"", with: "\"role\":\"controller\",\"role\":\"conductor\"")
        #expect(duplicated != text)
        #expect((try? SessionEnvelope<Tally>(json: Data(duplicated.utf8))) == nil)

        let sample = envelope(.sample(SampleBody(origin: LocalIdentity(name: "b").id, sample: Tally.Sample(level: 0.5), streamSequence: 1)))
        var object = try JSONSerialization.jsonObject(with: sample.json) as! [String: Any]
        var payload = object["payload"] as! [String: Any]
        payload["sample"] = ["level": 7]
        object["payload"] = payload
        #expect((try? SessionEnvelope<Tally>(json: JSONSerialization.data(withJSONObject: object))) == nil)
    }

    @Test func textFromAPeerIsCleanedAndBounded() {
        let hostile = "Kitchen\u{202E}TV\u{0007}\n\n  Screen" + String(repeating: "x", count: 200)
        let identity = PeerIdentity(publicKey: Curve25519.Signing.PrivateKey().publicKey, name: hostile)
        #expect(!identity.name.unicodeScalars.contains { $0.properties.generalCategory == .control || $0.properties.generalCategory == .format })
        #expect(identity.name.hasPrefix("KitchenTV Screen"))
        #expect(identity.name.count == PeerIdentity.maximumNameLength)
        #expect(PeerIdentity(publicKey: Curve25519.Signing.PrivateKey().publicKey, name: " \n ").name == "Unnamed device")
        let result = CommandResult(commandID: MessageID(), disposition: .refused, revision: 0, summary: "a\u{0000}b" + String(repeating: "y", count: 400))
        #expect(result.summary.count == CommandResult.maximumSummaryLength)
        #expect(!result.summary.contains("\u{0000}"))
    }

    @Test func aPeerIDIsItsKeysDigestAndCannotBeChosen() throws {
        let key = Curve25519.Signing.PrivateKey().publicKey
        let id = PeerID(publicKey: key)
        #expect(id.rawValue.count == 32)
        #expect(PeerID(rawValue: id.rawValue) == id)
        #expect(PeerID(rawValue: id.rawValue.uppercased()) == nil)
        #expect(PeerID(rawValue: "zz") == nil)
        let wire = WireIdentity(peerID: LocalIdentity(name: "other").id, publicKey: key.rawRepresentation.base64EncodedString(), name: "x")
        #expect(throws: HandshakeFailure.self) { try PeerIdentity(wire: wire) }
    }

    @Test func handshakeMessagesRefuseUnknownFieldsAndOversize() throws {
        let hello = HandshakeMessage.hello(.init(
            offer: Tally.offer, role: .controller, identity: LocalIdentity(name: "a").identity.wire, mode: .pair,
            commitment: "00", ephemeralKey: nil, nonce: nil
        ))
        #expect(try HandshakeMessage(frame: hello.frame) == hello)
        var object = try JSONSerialization.jsonObject(with: hello.frame.dropFirst()) as! [String: Any]
        var body = object["body"] as! [String: Any]
        body["grant"] = "all"
        object["body"] = body
        let smuggled = Data([FrameCodec.Kind.handshake.rawValue]) + (try JSONSerialization.data(withJSONObject: object))
        #expect(throws: HandshakeFailure.self) { try HandshakeMessage(frame: smuggled) }
        let huge = Data([FrameCodec.Kind.handshake.rawValue]) + Data(repeating: 0x20, count: FrameCodec.maximumHandshakeBytes + 1)
        #expect(throws: HandshakeFailure.self) { try HandshakeMessage(frame: huge) }
        #expect(throws: HandshakeFailure.self) { try HandshakeMessage(frame: Data([FrameCodec.Kind.sealed.rawValue, 0x7B, 0x7D])) }
    }

    @Test func aPairingCodeIsSixDigitsAndTypingIsForgiving() {
        let code = PairingCode(transcript: Data("transcript".utf8))
        #expect(code.digits.count == 6)
        #expect(code.description.count == 7)
        #expect(PairingCode(typed: code.description) == code)
        #expect(PairingCode(typed: "12345") == nil)
        #expect(PairingCode(typed: "12345a") == nil)
        #expect(PairingCode(typed: "١٢٣٤٥٦") == nil, "only ASCII digits")
        #expect(PairingCode(transcript: Data("other".utf8)) != code)
    }
}
