import Foundation

/// A validated item search. Matching and ordering are defined here, once, so every store and
/// adapter returns the same results for the same filter.
public struct ItemFilter: Hashable, Sendable {
    public static let maximumTextLength = 120
    public static let allowedLimits = 1...200

    /// Only items in this collection, or items in any collection when `nil`.
    public let collectionID: CollectionID?
    /// Case- and diacritic-insensitive text matched against titles and notes, or `nil` for all.
    public let text: String?
    public let includeArchived: Bool
    public let limit: Int

    public init(
        collectionID: CollectionID? = nil,
        text: String? = nil,
        includeArchived: Bool = false,
        limit: Int = 50
    ) throws(ValidationError) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed {
            guard trimmed.count <= Self.maximumTextLength else {
                throw .searchTextTooLong(limit: Self.maximumTextLength)
            }
            guard !trimmed.containsControlCharacter() else { throw .controlCharacter(in: .searchText) }
        }
        guard Self.allowedLimits.contains(limit) else { throw .resultLimitOutOfRange(allowed: Self.allowedLimits) }
        self.collectionID = collectionID
        self.text = trimmed?.isEmpty == false ? trimmed : nil
        self.includeArchived = includeArchived
        self.limit = limit
    }

    public func matches(_ item: LabItem) -> Bool {
        if let collectionID, item.collectionID != collectionID { return false }
        if item.isArchived && !includeArchived { return false }
        guard let text else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return item.title.value.range(of: text, options: options) != nil
            || item.note.value.range(of: text, options: options) != nil
    }

    /// The matching items ordered by title, then by ID, truncated to `limit`.
    public func select(from items: some Sequence<LabItem>) -> [LabItem] {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let sorted = items.filter(matches).sorted { lhs, rhs in
            switch lhs.title.value.compare(rhs.title.value, options: options) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
            }
        }
        return Array(sorted.prefix(limit))
    }
}
