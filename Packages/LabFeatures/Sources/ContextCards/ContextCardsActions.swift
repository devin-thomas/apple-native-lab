import ActionAtlas
import Foundation
import LabDomain

/// The reads and the set-aside the card and the Shortcut both call.
///
/// Set Aside archives one sample through `ActionAtlasActions`, after the screen check and the
/// confirmation. A screen-bound decision whose sample was replaced throws before that archive,
/// and the confirmation is not even asked. Nothing here holds the store.
public struct ContextCardsActions: Sendable {
    public let atlas: ActionAtlasActions
    /// The sample on screen at the moment of the check. The link publishes it.
    private let visible: @Sendable () -> VisibleEntityContext?

    public init(atlas: ActionAtlasActions, visible: @escaping @Sendable () -> VisibleEntityContext?) {
        self.atlas = atlas
        self.visible = visible
    }

    public func read(_ id: ItemID) async throws(ContextCardsError) -> LabItem {
        do { return try await atlas.item(id) } catch { throw .action(error) }
    }

    /// The sample as Shortcuts sees it, with its collection's title when the collection remains.
    public func entity(for item: LabItem) async throws(ContextCardsError) -> LabItemEntity {
        let collectionTitle: String
        do {
            collectionTitle = try await atlas.collection(item.collectionID).title.value
        } catch {
            switch error {
            case .missingCollection: collectionTitle = ""
            default: throw .action(error)
            }
        }
        return LabItemEntity(item, collectionTitle: collectionTitle)
    }

    /// Archives the proposal's sample, or refuses while it is no longer the one on screen.
    ///
    /// The screen is checked before the confirmation and again after it, so a replacement during
    /// the dialog also leaves the earlier sample unchanged. `confirm` is the system's
    /// confirmation for a Shortcut and an empty step for a button press in the app. If it throws,
    /// nothing is committed.
    public func setAside(
        _ proposal: DecisionProposal,
        request: AtlasRequest,
        confirm: @Sendable (ArchivePrompt) async throws -> Void
    ) async throws -> AtlasOutcome<LabItem> {
        guard !Task.isCancelled else { throw ContextCardsError.cancelled }
        do {
            return try await atlas.archiveItem(
                proposal.itemID, expected: proposal.revision, request: request
            ) { prompt in
                guard proposal.binds(self.visible()) else {
                    throw ContextCardsError.staleVisibleContent(title: proposal.title)
                }
                try await confirm(prompt)
                guard !Task.isCancelled else { throw ContextCardsError.cancelled }
                guard proposal.binds(self.visible()) else {
                    throw ContextCardsError.staleVisibleContent(title: proposal.title)
                }
            }
        } catch let error as ContextCardsError {
            throw error
        } catch let error as ActionAtlasError {
            throw ContextCardsError.action(error)
        } catch is CancellationError {
            throw ContextCardsError.cancelled
        } catch {
            throw ContextCardsError.cancelled
        }
    }
}
