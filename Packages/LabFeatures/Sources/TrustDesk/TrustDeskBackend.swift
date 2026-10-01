import LabDomain

/// What the desk needs from the host: reads and commits through the host's `OperationService`,
/// as the app UI. The desk never holds the store.
public protocol TrustDeskBackend: Sendable {
    func item(_ id: ItemID) async throws(TrustDeskError) -> LabItem?
    func collection(_ id: CollectionID) async throws(TrustDeskError) -> LabCollection?
    func perform(_ operation: DomainOperation, requestID: RequestID, names: [EntityReference: String]) async throws(TrustDeskError) -> ActionReceipt
}

/// What opening the sealed record did. A second open, after the note is already released and
/// the secret is stored, does not write a second receipt.
public enum OpenResult: Sendable {
    case committed(ActionReceipt)
    case alreadyOpen
}
