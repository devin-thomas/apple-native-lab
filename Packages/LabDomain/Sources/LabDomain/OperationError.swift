/// Why the service refused a request. A refused request changes nothing and records nothing, so
/// the caller can correct it and retry.
public enum OperationError: Error, Hashable, Sendable {
    case invalidPayload(ValidationError)
    case unauthorized(AuthorizationDenial)
    case notFound(EntityReference)
    /// The request ID already names a different request.
    case requestIDReused(RequestID)
    case ruleViolation(RuleViolation)
    case storeFailure(StoreFailure)
}

/// A business rule the current state does not allow.
public enum RuleViolation: Hashable, Sendable {
    case alreadyExists(EntityReference)
    case alreadyArchived(EntityReference)
    case notArchived(EntityReference)
    /// An archived entity cannot be edited; restore it first.
    case archived(EntityReference)
    /// A new item cannot be added to an archived collection.
    case collectionArchived(CollectionID)
    /// A new item cannot be added to a demo collection. A demo collection holds only the seed's
    /// samples, so Reset Demo never removes something a person created; add the item to one of
    /// the person's own collections instead.
    case demoCollection(CollectionID)
    /// The update would leave every field as it is.
    case noChanges(EntityReference)
    /// Cancel or restore was asked to change no lab alerts.
    case nothingToCancel
}

/// A store problem, without the underlying detail, which may contain paths or content.
public enum StoreFailure: Hashable, Sendable {
    case readFailed
    case commitFailed
    /// Concurrent writers kept invalidating the commit.
    case contention
}
