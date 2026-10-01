import Foundation
import LabDomain

/// The original fixture this experiment owns. The identifiers are stable, so a retry and a
/// relaunch name the same identity, collection, and item. The display name is not one of them.
public enum TrustDeskFixture {
    public static let identity = DeskIdentityID(rawValue: UUID(uuidString: "04104104-1041-4041-8041-041041041041")!)
    public static let collection = CollectionID(rawValue: UUID(uuidString: "04104104-1041-4041-8041-041041041042")!)
    public static let item = ItemID(rawValue: UUID(uuidString: "04104104-1041-4041-8041-041041041043")!)

    /// Request IDs for creating the fixture records. A retry of either creation returns its
    /// original receipt instead of adding a second record.
    public static let createCollectionRequest = RequestID(rawValue: UUID(uuidString: "04104104-1041-4041-8041-0410410410C1")!)
    public static let createItemRequest = RequestID(rawValue: UUID(uuidString: "04104104-1041-4041-8041-0410410410C2")!)

    public static let defaultDisplayName = "Desk fixture"
    public static let collectionTitle = "Trust Desk"
    public static let sealedNote = "Sealed. Local authorization has not released this record."
    public static let releasedNote = "Released. The fixture secret is in a scoped keychain record. This note holds no secret."

    /// The only secret the desk stores. It is fixture data, and it belongs in the keychain
    /// record, never in a receipt, a note, or a passkey reference.
    public static let secret = Data("trust-desk-fixture-secret".utf8)

    public static let keychainService = "lab.trust-desk.fixture"
    public static let relyingPartyID = "fixture.trust-desk.invalid"
    public static let relyingPartyName = "Trust Desk fixture"

    /// Shown beside every simulated passkey step. A system passkey is not what this is.
    public static let passkeySimulationLabel = "Passkey protocol simulation. This is not a system passkey, not an account sign-in, and not an exportable app secret."

    public static let localConfirmationLabel = "Local confirmation. This unlocks the sealed record in this app. It is not a passkey and not an account sign-in."
}
