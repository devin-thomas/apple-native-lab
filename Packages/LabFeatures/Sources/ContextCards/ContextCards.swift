import Foundation
import LabDomain

/// LAB-002 Context Cards: ask about the sample on screen, then set it aside from a card.
///
/// The decision is `DomainOperation.archiveItem` through Action Atlas, so the app and the typed
/// Shortcut share one authorization and receipt path (ADR-011, ADR-013). No Apple schema is
/// adopted: a lab sample is not a note, a book, or any other installed schema, and claiming one
/// fails the integration gate. Context resolution therefore stays unavailable, and the in-app
/// card and the Shortcut still complete the decision.
public enum ContextCards {
    public static let experimentID = "LAB-002"
    public static let title = "Context Cards"
    public static let symbol = "rectangle.and.text.magnifyingglass"

    /// Amber swatch, the sample the card associates first. This is the demo seed's id.
    public static let primarySampleID = ItemID(rawValue: UUID(uuidString: "DB666EF1-F642-43F1-B415-895B6ECFF693")!)
    /// Cobalt swatch, the sample that replaces Amber on screen. Also a demo seed id.
    public static let replacementSampleID = ItemID(rawValue: UUID(uuidString: "9B97BF2F-4D0B-4197-9CA8-36489DF40455")!)

    /// Info.plist key whose value is the `NSUserActivity` type, including the bundle prefix.
    public static let activityTypeInfoKey = "LabContextCardsActivityType"

    /// What the card and the Shortcut say when no schema resolved the sample on screen.
    public static let resolutionUnavailable = "Context resolution is unavailable."

    /// The sentence under a committed set-aside. The receipt summary comes first.
    public static func completedDialog(summary: String) -> String {
        "\(summary) \(resolutionUnavailable)"
    }

    /// The sentence for a read of one sample. The note is omitted when it is empty.
    public static func askDialog(title: String, note: String) -> String {
        let body = note.isEmpty ? "“\(title)”." : "“\(title)”. \(note)"
        return "\(body) \(resolutionUnavailable)"
    }

    /// What Set Aside asks, naming the sample the decision would change.
    public static func setAsidePrompt(title: String) -> String {
        "Set “\(title)” aside? It leaves normal view without being deleted, and its receipt in Native Lab offers an undo. Reset Demo restores it."
    }
}
