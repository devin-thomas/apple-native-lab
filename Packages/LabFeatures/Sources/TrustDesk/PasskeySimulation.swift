import CryptoKit
import Foundation

/// A reference to a credential. It names the record. It never contains secret bytes.
///
/// A passkey simulation is not an exportable app secret: `isExportableAppSecret` is always
/// false, and reading secret bytes for that kind is refused. A keychain reference names the
/// scoped record the fixture secret lives in; the bytes stay in the secret store.
public struct CredentialReference: Hashable, Sendable, Codable {
    public let identity: DeskIdentityID
    public let kind: CredentialKind
    public let account: String
    /// Set for a passkey simulation. A keychain record has none.
    public let relyingParty: String?

    public var isExportableAppSecret: Bool { false }
}

public enum CredentialKind: String, Hashable, Sendable, Codable {
    /// The fixture secret in the scoped keychain record.
    case scopedKeychainRecord
    /// A passkey ceremony against the fixture relying party. Not a system passkey.
    case passkeySimulation
}

/// The result of one simulated authentication. The signature is a response to the challenge.
/// It is not the private material, and the private material is not in this value.
public struct PasskeyAssertion: Hashable, Sendable {
    public let credentialID: Data
    public let userHandle: Data
    public let challenge: Data
    public let signature: Data
    public let displayName: String
    public let label: String
}

/// Registration and authentication against a fixture relying party.
///
/// The private material stays inside this simulator. `exportPrivateMaterial` always refuses,
/// which is the property the system passkey types also have: they expose a credential
/// identifier, not an exportable key. This is a labeled simulation. It does not present
/// `ASAuthorizationController` and it does not contact a network.
public final class PasskeySimulator: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [DeskIdentityID: Record] = [:]

    public init() {}

    public var label: String { TrustDeskFixture.passkeySimulationLabel }

    public func reference(for identity: DeskIdentityID) -> CredentialReference? {
        lock.lock()
        defer { lock.unlock() }
        return records[identity]?.reference
    }

    public func displayName(for identity: DeskIdentityID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return records[identity]?.displayName
    }

    /// Registers a credential for the identity. The user handle is the identity, not the
    /// display name. Registering again replaces the simulation for that identity only.
    @discardableResult
    public func register(identity: DeskIdentity) -> CredentialReference {
        lock.lock()
        defer { lock.unlock() }
        let record = Record(identity: identity)
        records[identity.id] = record
        return record.reference
    }

    /// Records a new display name on the existing credential. The credential identifier and
    /// the user handle stay as they were.
    public func noteDisplayName(_ displayName: String, for identity: DeskIdentityID) {
        lock.lock()
        defer { lock.unlock() }
        records[identity]?.displayName = displayName
    }

    public func authenticate(identity: DeskIdentityID) throws(TrustDeskError) -> PasskeyAssertion {
        lock.lock()
        defer { lock.unlock() }
        guard var record = records[identity] else { throw .passkeyNotRegistered }
        record.challengeCounter += 1
        let challenge = Data(repeating: record.challengeCounter, count: 32)
        let signature = Data(SHA256.hash(data: record.material + challenge))
        records[identity] = record
        return PasskeyAssertion(
            credentialID: record.credentialID,
            userHandle: identity.userHandle,
            challenge: challenge,
            signature: signature,
            displayName: record.displayName,
            label: TrustDeskFixture.passkeySimulationLabel
        )
    }

    /// Always refuses. A passkey simulation is not an app secret that can be copied out.
    public func exportPrivateMaterial(for reference: CredentialReference) throws(TrustDeskError) -> Data {
        _ = reference
        throw .passkeyIsNotAnAppSecret
    }

    public func reset(_ identity: DeskIdentityID) {
        lock.lock()
        defer { lock.unlock() }
        records[identity] = nil
    }

    private struct Record {
        let identity: DeskIdentityID
        let credentialID: Data
        let material: Data
        var displayName: String
        var challengeCounter: UInt8 = 0

        var reference: CredentialReference {
            CredentialReference(
                identity: identity,
                kind: .passkeySimulation,
                account: credentialID.base64EncodedString(),
                relyingParty: TrustDeskFixture.relyingPartyID
            )
        }

        init(identity: DeskIdentity) {
            self.identity = identity.id
            let handle = identity.id.userHandle
            credentialID = Data(SHA256.hash(data: Data("credential".utf8) + handle))
            material = Data(SHA256.hash(data: Data("material".utf8) + handle))
            displayName = identity.displayName
        }
    }
}
