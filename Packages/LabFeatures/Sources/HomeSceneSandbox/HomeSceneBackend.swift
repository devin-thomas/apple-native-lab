import LabDomain

/// What the sandbox needs from the host: reads and commits through the host's `OperationService`,
/// as the app UI. The sandbox never holds the store.
public protocol HomeSceneBackend: Sendable {
    func item(_ id: ItemID) async throws(HomeSceneError) -> LabItem?
    func collection(_ id: CollectionID) async throws(HomeSceneError) -> LabCollection?
    func perform(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(HomeSceneError) -> ActionReceipt
}
