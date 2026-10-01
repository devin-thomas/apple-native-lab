import Foundation
import LabDomain

/// Hosts supply their authorization-checked service, never a store or a system restriction API.
public protocol FrontierBackend: Sendable {
    func item(_ id: ItemID) async throws -> LabItem?
    func collection(_ id: CollectionID) async throws -> LabCollection?
    func perform(_ operation: DomainOperation, requestID: RequestID) async throws -> ActionReceipt
}

@MainActor
public final class FrontierDesk {
    private var running = false
    private struct Recorded {
        let capability: FrontierCapabilityCase
        let action: FrontierAction
        let operation: DomainOperation
    }
    private var requests: [RequestID: Recorded] = [:]
    public init() {}

    public func snapshot(_ capability: FrontierCapabilityCase, through backend: any FrontierBackend) async throws -> FrontierSnapshot {
        guard let item = try await backend.item(capability.itemID) else { return FrontierSnapshot() }
        guard item.collectionID == FrontierFixture.collection,
              item.title.value == capability.title,
              item.note.value.hasPrefix("Simulation: "),
              let data = item.note.value.dropFirst(12).data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(FrontierSnapshot.self, from: data),
              !snapshot.restricted || (capability == .screenTime && snapshot.active)
        else { throw FrontierError.invalidRecord }
        return snapshot
    }

    @discardableResult
    public func perform(_ action: FrontierAction, for capability: FrontierCapabilityCase,
                        through backend: any FrontierBackend, requestID: RequestID) async throws -> ActionReceipt {
        guard !Task.isCancelled else { throw FrontierError.cancelled }
        guard !running else { throw FrontierError.busy }
        running = true
        defer { running = false }
        if let previous = requests[requestID] {
            guard previous.capability == capability && previous.action == action else {
                throw OperationError.requestIDReused(requestID)
            }
            // Reauthorize duplicate requests through the domain service (ADR-011).
            return try await backend.perform(previous.operation, requestID: requestID)
        }
        guard requests.count < 256 else { throw FrontierError.sessionLimit }
        let item = try await backend.item(capability.itemID)
        let before = try await snapshot(capability, through: backend)
        let next = try before.applying(action, to: capability)
        let encoded = try JSONEncoder().encode(next)
        let note = try ItemNote("Simulation: " + String(decoding: encoded, as: UTF8.self))
        guard !Task.isCancelled else { throw FrontierError.cancelled }
        if try await backend.collection(FrontierFixture.collection) == nil {
            let draft = CollectionDraft(id: FrontierFixture.collection, title: try EntityTitle("Commercial Frontier Desk"))
            let receipt = try await backend.perform(.createCollection(draft: draft), requestID: FrontierFixture.collectionRequest)
            if case .conflict = receipt.status { throw FrontierError.conflict }
        }
        guard !Task.isCancelled else { throw FrontierError.cancelled }
        let operation: DomainOperation
        if let item {
            operation = .updateItem(id: item.id, expected: item.revision, changes: try ItemChanges(title: nil, note: note))
        } else {
            operation = .createItem(draft: ItemDraft(id: capability.itemID, in: FrontierFixture.collection,
                                                    title: try EntityTitle(capability.title), note: note))
        }
        let receipt = try await backend.perform(operation, requestID: requestID)
        if case .conflict = receipt.status { throw FrontierError.conflict }
        requests[requestID] = Recorded(capability: capability, action: action, operation: operation)
        return receipt
    }
}
