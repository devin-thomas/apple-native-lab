import Foundation
import LabDomain

/// Filters demo contents by title and note with the domain's own matching rules.
enum DemoSearch {
    static func filter(_ contents: [DemoCollection], text: String) -> [DemoCollection] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return contents }
        guard let filter = try? ItemFilter(text: text, includeArchived: true) else { return [] }
        return contents.compactMap { content in
            let items = content.items.filter(filter.matches)
            return items.isEmpty ? nil : DemoCollection(collection: content.collection, items: items)
        }
    }
}
