import CryptoKit
import Foundation

/// The running hash of every handshake frame, in the order sent, which both sides compute from the
/// same bytes. Signatures, the short code, and the session keys all bind to it, so changing any
/// handshake byte changes all three.
struct Transcript: Sendable {
    private var hash = SHA256()

    mutating func append(_ frame: Data) {
        var length = UInt32(frame.count).bigEndian
        withUnsafeBytes(of: &length) { hash.update(bufferPointer: $0) }
        hash.update(data: frame)
    }

    var digest: Data { Data(hash.finalize()) }
}

/// Signing contexts, so a signature made for one purpose is never valid for another.
enum SignatureContext: String {
    case joinerConfirm = "native-lab peer-session v1 joiner confirm"
    case hostAccept = "native-lab peer-session v1 host accept"

    func message(_ transcript: Data) -> Data { Data(rawValue.utf8) + transcript }
}

/// One side's ephemeral key agreement key and nonce, used for one handshake and then discarded.
struct EphemeralKeys: Sendable {
    let privateKey = Curve25519.KeyAgreement.PrivateKey()
    let nonce: Data = {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }()

    var publicKeyText: String { privateKey.publicKey.rawRepresentation.base64EncodedString() }
    var nonceText: String { nonce.base64EncodedString() }

    /// SHA-256 of the public key and the nonce, hex: the commitment a joiner sends before it has
    /// seen the host's key, so no one in the middle can choose a key after seeing both.
    var commitment: String { Self.commitment(publicKey: privateKey.publicKey.rawRepresentation, nonce: nonce) }

    static func commitment(publicKey: Data, nonce: Data) -> String {
        SHA256.hash(data: publicKey + nonce).map { String(format: "%02x", $0) }.joined()
    }

    static func publicKey(from text: String) throws(HandshakeFailure) -> Curve25519.KeyAgreement.PublicKey {
        guard let raw = Data(base64Encoded: text), let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) else {
            throw .malformed("The ephemeral key is not valid.")
        }
        return key
    }

    static func nonce(from text: String) throws(HandshakeFailure) -> Data {
        guard let nonce = Data(base64Encoded: text), nonce.count == 32 else { throw .malformed("The nonce is not valid.") }
        return nonce
    }

    func sharedSecret(with other: Curve25519.KeyAgreement.PublicKey) throws(HandshakeFailure) -> SharedSecret {
        do { return try privateKey.sharedSecretFromKeyAgreement(with: other) } catch { throw .cryptography }
    }
}

/// The short code both people see while pairing: six digits derived from the handshake transcript.
///
/// Because the joiner committed to its key before seeing the host's, a device in the middle that
/// runs two separate handshakes cannot make both show the same code, except by a one-in-a-million
/// chance per attempt. A person who copies the code from the host into the joiner, and allows the
/// pairing on the host only after the joiner says the code matched, therefore pins the real peer.
/// The code is never sent: each side computes it.
public struct PairingCode: Hashable, Sendable, CustomStringConvertible {
    public let digits: String

    init(transcript: Data) {
        let digest = SHA256.hash(data: Data("native-lab peer-session v1 code".utf8) + transcript)
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        digits = String(format: "%06u", value % 1_000_000)
    }

    /// Reads what a person typed: six digits, ignoring spaces. `nil` for anything else.
    public init?(typed: String) {
        let digits = typed.filter { !$0.isWhitespace }
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        self.digits = digits
    }

    /// Two groups of three, such as `482 913`.
    public var description: String { "\(digits.prefix(3)) \(digits.suffix(3))" }
}

/// Seals and opens session frames with keys derived from one handshake.
///
/// A sealed frame is `[0x02][counter: 8 bytes, big-endian][ChaCha20-Poly1305 ciphertext and tag]`.
/// The kind byte and counter are authenticated. Each direction has its own key, and the counter
/// is that direction's nonce: the receiver requires it to increase, so a replayed or reordered
/// frame is refused. It may skip values, so a transport that loses frames still works and the
/// session layer sees the loss as a sequence gap.
struct SecureChannel: Sendable {
    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var sendCounter: UInt64 = 0
    private var lastReceived: UInt64 = 0

    init(secret: SharedSecret, transcript: Data, isHost: Bool) {
        let toHost = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: transcript, sharedInfo: Data("native-lab peer-session v1 joiner to host".utf8), outputByteCount: 32
        )
        let toJoiner = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: transcript, sharedInfo: Data("native-lab peer-session v1 host to joiner".utf8), outputByteCount: 32
        )
        sendKey = isHost ? toJoiner : toHost
        receiveKey = isHost ? toHost : toJoiner
    }

    mutating func seal(_ plaintext: Data) throws(SecureChannelError) -> Data {
        sendCounter += 1
        return try Self.seal(plaintext, counter: sendCounter, key: sendKey)
    }

    mutating func open(_ frame: Data) throws(SecureChannelError) -> Data {
        guard frame.count > 9 + 16, frame.first == FrameCodec.Kind.sealed.rawValue else { throw .malformed }
        let header = Data(frame.prefix(9))
        let counter = header.dropFirst().reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard counter > lastReceived else { throw .replayed }
        do {
            let body = frame.dropFirst(9)
            let box = try ChaChaPoly.SealedBox(
                nonce: Self.nonce(counter), ciphertext: body.dropLast(16), tag: body.suffix(16)
            )
            let plaintext = try ChaChaPoly.open(box, using: receiveKey, authenticating: header)
            lastReceived = counter
            return plaintext
        } catch {
            throw .authenticationFailed
        }
    }

    private static func seal(_ plaintext: Data, counter: UInt64, key: SymmetricKey) throws(SecureChannelError) -> Data {
        var header = Data([FrameCodec.Kind.sealed.rawValue])
        withUnsafeBytes(of: counter.bigEndian) { header.append(contentsOf: $0) }
        do {
            let box = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce(counter), authenticating: header)
            return header + box.ciphertext + box.tag
        } catch {
            throw .authenticationFailed
        }
    }

    private static func nonce(_ counter: UInt64) -> ChaChaPoly.Nonce {
        var bytes = Data(repeating: 0, count: 4)
        withUnsafeBytes(of: counter.bigEndian) { bytes.append(contentsOf: $0) }
        // Twelve bytes is always a valid ChaChaPoly nonce.
        return try! ChaChaPoly.Nonce(data: bytes)
    }
}

public enum SecureChannelError: Error, Hashable, Sendable {
    case malformed
    /// The counter did not increase: a replayed, duplicated, or reordered frame.
    case replayed
    /// The frame was altered, or sealed with another key.
    case authenticationFailed
}
