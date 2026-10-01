import LabDomain
import Observation
import SwiftUI
import TrustDesk

/// LAB-041's names in the catalog and the sidebar.
enum TrustDeskExperiment {
    static let id = "LAB-041"
    static let title = "Trust Desk"
    static let symbol = "lock.shield"
}

/// One screen's Trust Desk. Every sealed-record open and every rename commits through
/// `LabLibrary.submit`, the same app-UI path as the rest of the lab. The passkey buttons
/// run the labeled simulation and do not submit a grant.
@MainActor
@Observable
final class TrustDeskSession {
    private let desk: TrustDesk
    private(set) var message: String?
    private(set) var receipt: ReceiptRecord?
    private(set) var assertionSummary: String?
    private(set) var isRunning = false

    @ObservationIgnored private var openRequest: RequestID?
    @ObservationIgnored private var renameRequest: RequestID?
    @ObservationIgnored private var resetRequest: RequestID?

    init(
        secrets: any SecretStore = KeychainSecretStore(),
        authorizer: any LocalAuthorizer = DeviceOwnerAuthorizer(),
        clock: any GrantClock = SystemGrantClock()
    ) {
        desk = TrustDesk(secrets: secrets, authorizer: authorizer, clock: clock)
    }

    var identity: DeskIdentity { desk.identity }
    var liveGrant: AuthorizationGrant? { desk.liveGrant() }
    var passkeyReference: CredentialReference? { desk.passkeyReference() }
    var passkeyLabel: String { desk.passkeySimulationLabel }
    var keychainReference: CredentialReference { desk.keychainReference }

    func refresh(in library: LabLibrary) async {
        do { try await desk.refresh(through: LibraryTrustDeskBackend(library: library)) } catch {
            message = describe(error)
        }
    }

    func rename(to name: String, in library: LabLibrary) async -> ReceiptRecord? {
        guard begin() else { return nil }
        defer { isRunning = false }
        let requestID = renameRequest ?? RequestID()
        renameRequest = requestID
        do {
            let receipt = try await desk.rename(to: name, through: LibraryTrustDeskBackend(library: library), requestID: requestID)
            renameRequest = nil
            return finish(receipt, in: library, sentence: "Display name updated. The identity is unchanged.")
        } catch {
            let sentence = describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
            return nil
        }
    }

    func authorizeWithDevice() async {
        guard begin() else { return }
        defer { isRunning = false }
        switch await desk.authorizeWithDevice() {
        case .granted:
            message = "This device authorized the sealed record. The grant expires in 60 seconds."
            LabAnnouncement(text: message ?? "").post()
        case .biometricFailed:
            message = "This device did not authorize. Nothing was changed. Confirm locally to continue, or try again."
            LabAnnouncement(failure: message ?? "").post()
        case .cancelled:
            message = TrustDeskError.cancelled.message
            LabAnnouncement(failure: message ?? "").post()
        case .unavailable(let reason):
            message = "\(reason) Confirm locally to continue. That confirmation is not a passkey."
            LabAnnouncement(failure: message ?? "").post()
        }
    }

    func confirmLocally() {
        guard !isRunning else { return }
        switch desk.confirmLocally() {
        case .granted:
            message = TrustDeskFixture.localConfirmationLabel
            LabAnnouncement(text: message ?? "").post()
        case .unavailable(let reason):
            message = reason
            LabAnnouncement(failure: reason).post()
        case .biometricFailed, .cancelled:
            message = TrustDeskError.cancelled.message
        }
    }

    func revokeGrant() {
        guard let grant = desk.liveGrant() else { return }
        desk.revoke(grant.id)
        message = "The local authorization was revoked. The record and its secret were kept."
        LabAnnouncement(text: message ?? "").post()
    }

    func openSealedRecord(in library: LabLibrary) async -> ReceiptRecord? {
        guard begin() else { return nil }
        defer { isRunning = false }
        let requestID = openRequest ?? RequestID()
        openRequest = requestID
        do {
            switch try await desk.openSealedRecord(through: LibraryTrustDeskBackend(library: library), requestID: requestID) {
            case .committed(let receipt):
                openRequest = nil
                return finish(receipt, in: library, sentence: "Opened the sealed record. The fixture secret is in a scoped keychain record.")
            case .alreadyOpen:
                message = "The sealed record is already open."
                LabAnnouncement(text: message ?? "").post()
                return nil
            }
        } catch {
            let sentence = describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
            return nil
        }
    }

    func registerPasskey() {
        let reference = desk.registerPasskey()
        assertionSummary = nil
        message = "\(desk.passkeySimulationLabel) Registered credential \(reference.account)."
        LabAnnouncement(text: "Registered a simulated passkey. It does not unlock the sealed record.").post()
    }

    func authenticatePasskey() {
        do {
            let assertion = try desk.authenticatePasskey()
            assertionSummary = "Authenticated. User handle \(TrustDeskFixture.identity.account). Challenge \(assertion.challenge.count) bytes. \(assertion.label)"
            message = assertionSummary
            LabAnnouncement(text: "Simulated passkey authentication finished. The sealed record stays locked until you authorize locally.").post()
        } catch {
            let sentence = describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
        }
    }

    func reset(in library: LabLibrary) async -> ReceiptRecord? {
        guard begin() else { return nil }
        defer { isRunning = false }
        let requestID = resetRequest ?? RequestID()
        resetRequest = requestID
        assertionSummary = nil
        do {
            let receipt = try await desk.resetDesk(through: LibraryTrustDeskBackend(library: library), requestID: requestID)
            resetRequest = nil
            message = "Reset the desk. Other lab records were kept."
            LabAnnouncement(text: message ?? "").post()
            guard let receipt else { return nil }
            return finish(receipt, in: library, sentence: message ?? "")
        } catch {
            let sentence = describe(error)
            message = sentence
            LabAnnouncement(failure: sentence).post()
            return nil
        }
    }

    private func begin() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    private func finish(_ receipt: ActionReceipt, in library: LabLibrary, sentence: String) -> ReceiptRecord {
        let record = ReceiptRecord(
            receipt: receipt,
            recordedAt: .now,
            names: [
                .item(TrustDeskFixture.item): identity.displayName,
                .collection(TrustDeskFixture.collection): TrustDeskFixture.collectionTitle,
            ]
        )
        let listed = library.receipt(id: receipt.operationID) ?? record
        self.receipt = listed
        message = sentence
        LabAnnouncement(text: sentence).post()
        return listed
    }

    private func describe(_ error: any Error) -> String {
        guard let error = error as? TrustDeskError else { return LibraryMessages.describe(error) }
        if case .operation(let operation) = error { return LibraryMessages.describe(operation) }
        return error.message
    }
}

/// The host's operation service, as the app UI. Trust Desk never holds the store.
struct LibraryTrustDeskBackend: TrustDeskBackend {
    let library: LabLibrary

    func item(_ id: ItemID) async throws(TrustDeskError) -> LabItem? {
        let service = try await opened()
        do { return try await service.item(id, as: LabDataService.appUI) } catch .notFound {
            return nil
        } catch {
            throw .operation(error)
        }
    }

    func collection(_ id: CollectionID) async throws(TrustDeskError) -> LabCollection? {
        let service = try await opened()
        do { return try await service.collection(id, as: LabDataService.appUI) } catch .notFound {
            return nil
        } catch {
            throw .operation(error)
        }
    }

    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(TrustDeskError) -> ActionReceipt {
        do {
            return try await library.submit(operation, requestID: requestID, authority: .userAction, names: names).receipt
        } catch let failure as LabLibrary.SubmitFailure {
            switch failure {
            case .unavailable(let reason): throw .labUnavailable(reason)
            case .refused(let error): throw .operation(error)
            }
        } catch {
            throw .labUnavailable("The lab could not commit the change.")
        }
    }

    private func opened() async throws(TrustDeskError) -> LabDataService {
        do { return try await library.openedService() } catch let failure as LabLibrary.SubmitFailure {
            switch failure {
            case .unavailable(let reason): throw .labUnavailable(reason)
            case .refused(let error): throw .operation(error)
            }
        } catch {
            throw .labUnavailable("The lab store is still opening. Try again.")
        }
    }
}
