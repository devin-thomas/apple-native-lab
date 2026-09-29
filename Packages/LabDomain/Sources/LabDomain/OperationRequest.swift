/// One requested state change, as an adapter submits it to `OperationService`.
///
/// Deliberately not `Codable`: the actor is assigned by the adapter that receives a request, never
/// read from a payload. Serialize the `operation` alone when a request crosses a process boundary.
public struct OperationRequest: Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let id: RequestID
    public let operation: DomainOperation
    public let actor: ActorScope
    public let schemaVersion: Int

    public init(
        id: RequestID,
        operation: DomainOperation,
        actor: ActorScope,
        schemaVersion: Int = OperationRequest.currentSchemaVersion
    ) {
        self.id = id
        self.operation = operation
        self.actor = actor
        self.schemaVersion = schemaVersion
    }

    /// The revision the request expects its target to have, or `nil` for a creation.
    public var expectedRevision: Revision? { operation.expectedRevision }
}

/// The part of a request that a receipt records and that a retry must repeat exactly.
///
/// A request ID is bound to this content. Reusing the ID with a different operation, expected
/// revision, schema version, or adapter kind is refused rather than treated as a retry. Grants are
/// not part of it, so a retry with a refreshed grant still returns the original receipt.
public struct AdmittedRequest: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public let adapter: AdapterKind
    public let operation: DomainOperation

    init(_ request: OperationRequest) {
        schemaVersion = request.schemaVersion
        adapter = request.actor.adapter
        operation = request.operation
    }
}
