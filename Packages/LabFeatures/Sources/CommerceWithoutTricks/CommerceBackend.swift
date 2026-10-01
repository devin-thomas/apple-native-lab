import LabDomain

/// What the commerce desk needs from the host: reads and commits through the host's
/// `OperationService`, as the app UI. The desk never holds the store.
public protocol CommerceBackend: Sendable {
    func item(_ id: ItemID) async throws(CommerceError) -> LabItem?
    func collection(_ id: CollectionID) async throws(CommerceError) -> LabCollection?
    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(CommerceError) -> ActionReceipt
}

/// What committing an entitlement change did.
public enum CommerceCommit: Sendable {
    case committed(ActionReceipt)
    case unchanged
}
