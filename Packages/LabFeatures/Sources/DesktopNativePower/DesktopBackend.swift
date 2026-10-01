import Foundation
import LabDomain

/// What Desktop Native Power needs from the host: reads and commits through the host's own
/// `OperationService`, as the adapter that received the request.
///
/// The host implements it with the same library its views use, so a menu, a service, and the
/// allowlisted intent leave receipts in the same list. This module never holds the store.
public protocol DesktopBackend: Sendable {
    func collection(_ id: CollectionID, as adapter: AdapterKind) async throws(DesktopPowerError) -> LabCollection?
    func item(_ id: ItemID, as adapter: AdapterKind) async throws(DesktopPowerError) -> LabItem?
    func items(in collectionID: CollectionID, as adapter: AdapterKind) async throws(DesktopPowerError) -> [LabItem]
    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String],
        as adapter: AdapterKind
    ) async throws(DesktopPowerError) -> ActionReceipt
    func receipt(for requestID: RequestID, as adapter: AdapterKind) async throws(DesktopPowerError) -> ActionReceipt?
}

/// A backend over an `OperationService`. Tests use it; the Mac host uses its library instead.
public struct ServiceDesktopBackend: DesktopBackend {
    private let service: OperationService

    public init(service: OperationService) {
        self.service = service
    }

    public func collection(_ id: CollectionID, as adapter: AdapterKind) async throws(DesktopPowerError) -> LabCollection? {
        do {
            return try await service.findCollection(id, as: actor(adapter))
        } catch .notFound {
            return nil
        } catch {
            throw DesktopPowerError(error)
        }
    }

    public func item(_ id: ItemID, as adapter: AdapterKind) async throws(DesktopPowerError) -> LabItem? {
        do {
            return try await service.findItem(id, as: actor(adapter))
        } catch .notFound {
            return nil
        } catch {
            throw DesktopPowerError(error)
        }
    }

    public func items(in collectionID: CollectionID, as adapter: AdapterKind) async throws(DesktopPowerError) -> [LabItem] {
        do {
            let filter = try ItemFilter(collectionID: collectionID, includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
            return try await service.findItems(filter, as: actor(adapter))
        } catch let error as OperationError {
            throw DesktopPowerError(error)
        } catch {
            throw .unavailable
        }
    }

    public func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String],
        as adapter: AdapterKind
    ) async throws(DesktopPowerError) -> ActionReceipt {
        do {
            return try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor(adapter)))
        } catch {
            throw DesktopPowerError(error)
        }
    }

    public func receipt(for requestID: RequestID, as adapter: AdapterKind) async throws(DesktopPowerError) -> ActionReceipt? {
        do {
            return try await service.findReceipt(for: requestID, as: actor(adapter))
        } catch {
            throw DesktopPowerError(error)
        }
    }

    private func actor(_ adapter: AdapterKind) -> ActorScope {
        ActorScope(adapter: adapter, grants: Set(Permission.allCases))
    }
}

/// A backend that cannot reach a store. Imports fail closed and record nothing.
public struct UnavailableDesktopBackend: DesktopBackend {
    public init() {}

    public func collection(_ id: CollectionID, as adapter: AdapterKind) async throws(DesktopPowerError) -> LabCollection? {
        throw .unavailable
    }

    public func item(_ id: ItemID, as adapter: AdapterKind) async throws(DesktopPowerError) -> LabItem? {
        throw .unavailable
    }

    public func items(in collectionID: CollectionID, as adapter: AdapterKind) async throws(DesktopPowerError) -> [LabItem] {
        throw .unavailable
    }

    public func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String],
        as adapter: AdapterKind
    ) async throws(DesktopPowerError) -> ActionReceipt {
        throw .unavailable
    }

    public func receipt(for requestID: RequestID, as adapter: AdapterKind) async throws(DesktopPowerError) -> ActionReceipt? {
        throw .unavailable
    }
}

extension DesktopPowerError {
    public init(_ error: OperationError) {
        switch error {
        case .unauthorized:
            self = .notAuthorized
        case .invalidPayload:
            self = .invalidText
        case .ruleViolation(.alreadyExists), .requestIDReused:
            self = .alreadyStored
        case .storeFailure, .notFound, .ruleViolation:
            self = .unavailable
        }
    }
}
