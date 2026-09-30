import LabDomain

/// What Portable Objects needs from the host: reads and commits through the host's own
/// `OperationService`, as the app UI.
///
/// The host implements it with the same library its views use, so an import's receipt joins the
/// session's receipts like any other change. Portable Objects never holds the store.
public protocol PortableObjectsBackend: Sendable {
    /// The item with this ID, or `nil` when the lab has none.
    func item(_ id: ItemID) async throws(PortableObjectError) -> LabItem?
    /// The collection with this ID, or `nil` when the lab has none.
    func collection(_ id: CollectionID) async throws(PortableObjectError) -> LabCollection?
    /// Every item, archived or not.
    func items() async throws(PortableObjectError) -> [LabItem]
    /// Every collection, archived or not.
    func collections() async throws(PortableObjectError) -> [LabCollection]
    /// The receipt recorded for a request, or `nil` when it was never admitted.
    func receipt(for requestID: RequestID) async throws(PortableObjectError) -> ActionReceipt?
    /// Commits one request and returns its receipt, or the receipt already recorded for its ID.
    /// `names` titles the entities involved, for the host's receipt views.
    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(PortableObjectError) -> ActionReceipt
}

/// A backend over an `OperationService`, as one actor. Tests and fixture replays use it; the host
/// uses its library instead, so receipts reach its receipt views.
public struct ServiceBackend: PortableObjectsBackend {
    private let service: OperationService
    private let actor: ActorScope

    public init(service: OperationService, actor: ActorScope) {
        self.service = service
        self.actor = actor
    }

    public func item(_ id: ItemID) async throws(PortableObjectError) -> LabItem? {
        do { return try await service.findItem(id, as: actor) } catch .notFound { return nil } catch { throw PortableObjectError(error) }
    }

    public func collection(_ id: CollectionID) async throws(PortableObjectError) -> LabCollection? {
        do { return try await service.findCollection(id, as: actor) } catch .notFound { return nil } catch { throw PortableObjectError(error) }
    }

    public func items() async throws(PortableObjectError) -> [LabItem] {
        do {
            let filter = try ItemFilter(includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
            return try await service.findItems(filter, as: actor)
        } catch let error as OperationError {
            throw PortableObjectError(error)
        } catch {
            throw .storeUnavailable
        }
    }

    public func collections() async throws(PortableObjectError) -> [LabCollection] {
        // The service reads collections one at a time; the items name the ones in use.
        let items = try await items()
        var collections: [LabCollection] = []
        for id in Set(items.map(\.collectionID)) {
            if let collection = try await collection(id) { collections.append(collection) }
        }
        return collections
    }

    public func receipt(for requestID: RequestID) async throws(PortableObjectError) -> ActionReceipt? {
        do { return try await service.findReceipt(for: requestID, as: actor) } catch { throw PortableObjectError(error) }
    }

    public func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(PortableObjectError) -> ActionReceipt {
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw PortableObjectError(error)
        }
    }
}

extension PortableObjectError {
    /// The service's refusal of an import, as a reason about the import.
    public init(_ error: OperationError) {
        switch error {
        case .unauthorized: self = .notAuthorized
        case .notFound, .ruleViolation(.collectionArchived), .ruleViolation(.demoCollection): self = .destinationUnavailable
        case .ruleViolation(.alreadyExists): self = .stateChanged
        case .ruleViolation(.archived): self = .storedCopyArchived
        case .ruleViolation(.noChanges): self = .nothingToImport
        case .ruleViolation, .requestIDReused: self = .identifierConflict
        case .invalidPayload(let reason): self = .invalidTitle(reason)
        case .storeFailure: self = .storeUnavailable
        }
    }
}
