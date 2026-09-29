import SwiftUI

/// Every Action Atlas action, one for each App Intent. The in-app action browser lists them all,
/// so each runs without Siri, Shortcuts, or Apple Intelligence.
enum AtlasAction: String, CaseIterable, Identifiable, Hashable {
    case createCollection
    case createItem
    case findItems
    case getItem
    case updateItem
    case archiveItem
    case restoreItem
    case exportItem

    enum Group: String, CaseIterable {
        case create = "Create"
        case find = "Find"
        case change = "Change"
        case share = "Share"
    }

    var id: String { rawValue }

    /// The same title the action has in Shortcuts.
    var title: String {
        switch self {
        case .createCollection: "Create Lab Collection"
        case .createItem: "Create Lab Item"
        case .findItems: "Find Lab Items"
        case .getItem: "Get Lab Item"
        case .updateItem: "Update Lab Item"
        case .archiveItem: "Archive Lab Item"
        case .restoreItem: "Restore Lab Item"
        case .exportItem: "Export Lab Item"
        }
    }

    var symbol: String {
        switch self {
        case .createCollection: "folder.badge.plus"
        case .createItem: "doc.badge.plus"
        case .findItems: "magnifyingglass"
        case .getItem: "doc.text.magnifyingglass"
        case .updateItem: "pencil"
        case .archiveItem: "archivebox"
        case .restoreItem: "arrow.uturn.backward"
        case .exportItem: "square.and.arrow.up"
        }
    }

    var summary: String {
        switch self {
        case .createCollection: "A collection of your own. Demo collections hold only the samples."
        case .createItem: "An item in one of your collections."
        case .findItems: "Items whose title or note contains some text."
        case .getItem: "The current state of one item."
        case .updateItem: "A new title, note, or both, at the revision you saw."
        case .archiveItem: "Hides an item without deleting it. The receipt offers an undo."
        case .restoreItem: "Returns an archived item to normal view."
        case .exportItem: "One item as versioned JSON or plain text. Nothing is uploaded."
        }
    }

    var group: Group {
        switch self {
        case .createCollection, .createItem: .create
        case .findItems, .getItem: .find
        case .updateItem, .archiveItem, .restoreItem: .change
        case .exportItem: .share
        }
    }

    static func matching(_ text: String) -> [AtlasAction] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return allCases }
        return allCases.filter {
            $0.title.localizedStandardContains(needle) || $0.summary.localizedStandardContains(needle)
        }
    }
}

/// One action in the browser: its Shortcuts title, symbol, and what it does.
struct AtlasActionRow: View {
    let action: AtlasAction

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.headline)
                Text(action.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: action.symbol)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// What the browser says about itself, above the actions.
struct AtlasBrowserHeader: View {
    var body: some View {
        Text("Each action here is also a Shortcuts action. Both run the same operation and leave the same receipt. Siri, Shortcuts, and Apple Intelligence are not needed here.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
