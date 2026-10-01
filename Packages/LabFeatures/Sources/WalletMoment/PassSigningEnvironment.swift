import Foundation

/// Where a signed `.pkpass` would come from. The client never embeds a pass-signing private key;
/// an operator supplies an external tool (or a test double) through this seam.
///
/// Default: `UnavailablePassSigner`. Production signing stays outside CoreLocal (FrontierOptional).
public protocol PassSigningEnvironment: Sendable {
    /// Whether an operator has configured this environment. False means the unsigned preview is
    /// the only path.
    var isConfigured: Bool { get }

    /// Asks the environment for signed pass bytes for `definition`. Never accepts raw private-key
    /// material as an argument. Throws `WalletMomentError.signingUnavailable` when not configured.
    func signedPass(for definition: PassDefinition) async throws(WalletMomentError) -> SignedPassArtifact
}

/// Result of an operator signing request. The bytes are opaque; their provenance says how they
/// were produced so a fixture path is never mistaken for a live Wallet install.
public struct SignedPassArtifact: Hashable, Sendable {
    public enum Provenance: String, Hashable, Sendable {
        /// Produced by an operator-supplied external tool. Still not device proof of Wallet.
        case operatorTool
        /// A clearly labeled test double. Not a live signature.
        case testDouble
    }

    public let bytes: Data
    public let provenance: Provenance
    public let note: String

    public init(bytes: Data, provenance: Provenance, note: String) {
        self.bytes = bytes
        self.provenance = provenance
        self.note = note
    }
}

/// The default signing environment: nothing is configured, so signing is refused and the unsigned
/// preview remains the usable path.
public struct UnavailablePassSigner: PassSigningEnvironment {
    public init() {}

    public var isConfigured: Bool { false }

    public func signedPass(for definition: PassDefinition) async throws(WalletMomentError) -> SignedPassArtifact {
        _ = definition
        throw .signingUnavailable
    }
}

/// An explicitly injected operator service. Hosts leave this unconfigured. The adapter owns
/// transport, cancellation and bounded output; no executable path or key enters this module.
public struct OperatorPassSigner: PassSigningEnvironment {
    private let sign: (@Sendable (PassDefinition) async throws -> Data)?
    public static let maximumArtifactBytes = 2_000_000

    public init(sign: (@Sendable (PassDefinition) async throws -> Data)? = nil) {
        self.sign = sign
    }

    public var isConfigured: Bool { sign != nil }

    public func signedPass(for definition: PassDefinition) async throws(WalletMomentError) -> SignedPassArtifact {
        guard let sign else { throw .signingUnavailable }
        _ = try PassValidator.validate(definition)
        guard !Task.isCancelled else { throw .signingFailed }
        let bytes: Data
        do { bytes = try await sign(definition) }
        catch { throw .signingFailed }
        guard !Task.isCancelled, !bytes.isEmpty, bytes.count <= Self.maximumArtifactBytes else {
            throw .signingFailed
        }
        // This is an archive envelope check, not verification of an Apple signature.
        guard bytes.starts(with: [0x50, 0x4b, 0x03, 0x04]) else { throw .signingFailed }
        return SignedPassArtifact(
            bytes: bytes,
            provenance: .operatorTool,
            note: "Operator-provided archive. Signature and Wallet installation are unverified."
        )
    }
}

/// A test-only signing double that returns labeled fixture bytes. It proves the operator seam
/// without embedding a real key. Production hosts must not use it.
public struct TestPassSigner: PassSigningEnvironment {
    public let artifact: SignedPassArtifact

    public init(bytes: Data = Data("LAB-038-test-pass-not-a-real-signature".utf8)) {
        self.artifact = SignedPassArtifact(
            bytes: bytes,
            provenance: .testDouble,
            note: "Test double. Labeled fixture bytes, not a live Wallet signature."
        )
    }

    public var isConfigured: Bool { true }

    public func signedPass(for definition: PassDefinition) async throws(WalletMomentError) -> SignedPassArtifact {
        _ = try PassValidator.validate(definition)
        return artifact
    }
}
