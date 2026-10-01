import Foundation
import LabDomain
import Synchronization

/// What a local authorization became. Only `.granted` holds a grant, and only after the
/// attempt succeeded. Biometric failure, cancellation, and unavailability leave every record,
/// secret, and earlier grant as they were.
public enum LocalAuthorizationOutcome: Sendable {
    case granted(AuthorizationGrant)
    case biometricFailed
    case cancelled
    case unavailable(String)
}

/// The Trust Desk operation: a stable identity, a local grant, a scoped secret, and a passkey
/// simulation that does not unlock the sealed record.
///
/// Renames and the sealed-record open commit through `TrustDeskBackend`, which the host
/// implements with `LabLibrary.submit`. A passkey assertion is not a grant. Reset removes only
/// this desk's secret, simulation, and grants, and restores the fixture title and note.
public final class TrustDesk: @unchecked Sendable {
    private let secrets: any SecretStore
    private let authorizer: any LocalAuthorizer
    private let grants: DeskGrantLedger
    private let passkeys = PasskeySimulator()
    private let displayName: Mutex<String>

    public init(
        secrets: any SecretStore,
        authorizer: any LocalAuthorizer,
        clock: any GrantClock = SystemGrantClock(),
        displayName: String = TrustDeskFixture.defaultDisplayName
    ) {
        self.secrets = secrets
        self.authorizer = authorizer
        grants = DeskGrantLedger(clock: clock)
        self.displayName = Mutex(displayName)
    }

    public var identity: DeskIdentity {
        DeskIdentity(id: TrustDeskFixture.identity, displayName: displayName.withLock { $0 })
    }

    public var passkeySimulationLabel: String { passkeys.label }

    public var keychainReference: CredentialReference {
        CredentialReference(
            identity: TrustDeskFixture.identity,
            kind: .scopedKeychainRecord,
            account: TrustDeskFixture.identity.account,
            relyingParty: nil
        )
    }

    // MARK: Identity

    /// Reads the stored title, when the fixture item exists, so a relaunch shows the name the
    /// last rename committed. The identity identifier does not come from the title.
    public func refresh(through backend: any TrustDeskBackend) async throws(TrustDeskError) {
        guard let item = try await backend.item(TrustDeskFixture.item) else { return }
        displayName.withLock { $0 = item.title.value }
        passkeys.noteDisplayName(item.title.value, for: TrustDeskFixture.identity)
    }

    /// Changes the display name. The identity, the keychain account, and any passkey user
    /// handle stay the same. An invalid name changes nothing.
    @discardableResult
    public func rename(to rawName: String, through backend: any TrustDeskBackend, requestID: RequestID) async throws(TrustDeskError) -> ActionReceipt {
        try cancelled()
        let title = try validatedTitle(rawName)
        if let created = try await ensureFixture(through: backend, title: title) {
            displayName.withLock { $0 = title.value }
            passkeys.noteDisplayName(title.value, for: TrustDeskFixture.identity)
            return created
        }
        let item = try await requireItem(through: backend)
        guard item.title != title else { throw .displayNameUnchanged }
        let update = try itemChanges(title: title, note: nil)
        let receipt = try await backend.perform(
            .updateItem(id: item.id, expected: item.revision, changes: update),
            requestID: requestID,
            names: names(title: title.value)
        )
        guard case .committed = receipt.status else { return receipt }
        displayName.withLock { $0 = title.value }
        passkeys.noteDisplayName(title.value, for: TrustDeskFixture.identity)
        return receipt
    }

    // MARK: Local authorization

    /// Asks this device. A failure does not revoke grants, delete the secret, or edit the record.
    public func authorizeWithDevice() async -> LocalAuthorizationOutcome {
        switch await authorizer.authorize() {
        case .succeeded:
            return issue(.deviceOwner)
        case .biometricFailed:
            return .biometricFailed
        case .cancelled:
            return .cancelled
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }

    /// The fallback. It is an explicit confirmation in this app, not a biometric and not a passkey.
    public func confirmLocally() -> LocalAuthorizationOutcome {
        issue(.localConfirmation)
    }

    public func revoke(_ id: UUID) {
        grants.revoke(id)
    }

    public func liveGrant() -> AuthorizationGrant? {
        grants.liveGrant(for: TrustDeskFixture.identity, purpose: .openSealedRecord)
    }

    // MARK: Sealed record

    /// Opens the sealed record when a live grant exists: one `updateItem` through the backend,
    /// then the fixture secret in the scoped keychain record. A refusal writes neither.
    public func openSealedRecord(through backend: any TrustDeskBackend, requestID: RequestID) async throws(TrustDeskError) -> OpenResult {
        try cancelled()
        guard liveGrant() != nil else { throw grants.refusal(for: TrustDeskFixture.identity, purpose: .openSealedRecord) }
        let title = try validatedTitle(identity.displayName)
        _ = try await ensureFixture(through: backend, title: title)
        let item = try await requireItem(through: backend)
        let released = try itemNote(TrustDeskFixture.releasedNote)
        let account = TrustDeskFixture.identity.account
        if item.note == released {
            if try secrets.read(account: account) != TrustDeskFixture.secret {
                try secrets.write(TrustDeskFixture.secret, account: account)
            }
            return .alreadyOpen
        }
        try cancelled()
        // The secret is written only after the note update commits. A conflict or a refusal
        // leaves the keychain as it was. If the write fails after a commit, the note is put
        // back so the record is not "released" without its secret.
        let update = try itemChanges(title: nil, note: released)
        let receipt = try await backend.perform(
            .updateItem(id: item.id, expected: item.revision, changes: update),
            requestID: requestID,
            names: names(title: item.title.value)
        )
        guard case .committed = receipt.status else { return .committed(receipt) }
        do {
            try secrets.write(TrustDeskFixture.secret, account: account)
        } catch let failure {
            let sealed = try itemNote(TrustDeskFixture.sealedNote)
            let revert = try itemChanges(title: nil, note: sealed)
            _ = try? await backend.perform(
                .updateItem(id: item.id, expected: receipt.changes.first?.newRevision ?? item.revision, changes: revert),
                requestID: RequestID(),
                names: names(title: item.title.value)
            )
            throw failure
        }
        return .committed(receipt)
    }

    /// The fixture secret, only from the keychain reference. A passkey reference is refused.
    public func copyAppSecret(_ reference: CredentialReference) throws(TrustDeskError) -> Data? {
        guard reference.kind == .scopedKeychainRecord else { throw .passkeyIsNotAnAppSecret }
        guard reference.identity == TrustDeskFixture.identity else { throw .passkeyIsNotAnAppSecret }
        return try secrets.read(account: reference.account)
    }

    // MARK: Passkey simulation

    @discardableResult
    public func registerPasskey() -> CredentialReference {
        passkeys.register(identity: identity)
    }

    public func passkeyReference() -> CredentialReference? {
        passkeys.reference(for: TrustDeskFixture.identity)
    }

    public func authenticatePasskey() throws(TrustDeskError) -> PasskeyAssertion {
        try passkeys.authenticate(identity: TrustDeskFixture.identity)
    }

    public func exportPasskeyMaterial(_ reference: CredentialReference) throws(TrustDeskError) -> Data {
        try passkeys.exportPrivateMaterial(for: reference)
    }

    // MARK: Reset

    /// Removes this desk's secret, simulated passkey, and grants, and restores the fixture
    /// title and note when they differ. Other lab records are not read for deletion.
    @discardableResult
    public func resetDesk(through backend: any TrustDeskBackend, requestID: RequestID) async throws(TrustDeskError) -> ActionReceipt? {
        try cancelled()
        try secrets.remove(account: TrustDeskFixture.identity.account)
        passkeys.reset(TrustDeskFixture.identity)
        grants.revokeAll()
        guard let item = try await backend.item(TrustDeskFixture.item) else {
            displayName.withLock { $0 = TrustDeskFixture.defaultDisplayName }
            return nil
        }
        let title = try validatedTitle(TrustDeskFixture.defaultDisplayName)
        let sealedNote = try itemNote(TrustDeskFixture.sealedNote)
        let titleChange = item.title == title ? nil : title
        let noteChange = item.note == sealedNote ? nil : sealedNote
        guard titleChange != nil || noteChange != nil else {
            displayName.withLock { $0 = title.value }
            return nil
        }
        let update = try itemChanges(title: titleChange, note: noteChange)
        let receipt = try await backend.perform(
            .updateItem(id: item.id, expected: item.revision, changes: update),
            requestID: requestID,
            names: names(title: title.value)
        )
        if case .committed = receipt.status {
            displayName.withLock { $0 = title.value }
        }
        return receipt
    }

    // MARK: Support

    private func cancelled() throws(TrustDeskError) {
        if Task.isCancelled { throw .cancelled }
    }

    private func issue(_ method: AuthorizationMethod) -> LocalAuthorizationOutcome {
        do {
            let grant = try grants.issue(for: TrustDeskFixture.identity, purpose: .openSealedRecord, method: method)
            return .granted(grant)
        } catch {
            return .unavailable(error.message)
        }
    }

    /// Creates the fixture collection and item when they are missing. Returns the item-creation
    /// receipt when this call created the item, so the caller can keep that receipt.
    private func ensureFixture(through backend: any TrustDeskBackend, title: EntityTitle) async throws(TrustDeskError) -> ActionReceipt? {
        if try await backend.collection(TrustDeskFixture.collection) == nil {
            let collectionTitle = try validatedTitle(TrustDeskFixture.collectionTitle)
            _ = try await backend.perform(
                .createCollection(draft: CollectionDraft(id: TrustDeskFixture.collection, title: collectionTitle)),
                requestID: TrustDeskFixture.createCollectionRequest,
                names: [.collection(TrustDeskFixture.collection): collectionTitle.value]
            )
        }
        if try await backend.item(TrustDeskFixture.item) == nil {
            let sealed = try itemNote(TrustDeskFixture.sealedNote)
            return try await backend.perform(
                .createItem(draft: ItemDraft(
                    id: TrustDeskFixture.item,
                    in: TrustDeskFixture.collection,
                    title: title,
                    note: sealed
                )),
                requestID: TrustDeskFixture.createItemRequest,
                names: names(title: title.value)
            )
        }
        return nil
    }

    private func requireItem(through backend: any TrustDeskBackend) async throws(TrustDeskError) -> LabItem {
        guard let item = try await backend.item(TrustDeskFixture.item) else {
            throw .labUnavailable("The desk record was not stored.")
        }
        return item
    }

    private func validatedTitle(_ raw: String) throws(TrustDeskError) -> EntityTitle {
        do { return try EntityTitle(raw) } catch { throw .invalidDisplayName(error) }
    }

    private func itemNote(_ raw: String) throws(TrustDeskError) -> ItemNote {
        do { return try ItemNote(raw) } catch { throw .operation(.invalidPayload(error)) }
    }

    private func itemChanges(title: EntityTitle?, note: ItemNote?) throws(TrustDeskError) -> ItemChanges {
        do { return try ItemChanges(title: title, note: note) } catch { throw .operation(.invalidPayload(error)) }
    }

    private func names(title: String) -> [EntityReference: String] {
        [
            .item(TrustDeskFixture.item): title,
            .collection(TrustDeskFixture.collection): TrustDeskFixture.collectionTitle,
        ]
    }
}
