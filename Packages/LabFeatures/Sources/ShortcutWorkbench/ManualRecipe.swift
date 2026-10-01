import Foundation

/// Manual recipe cards shown when Shortcuts is unavailable. They describe the same walkthrough
/// the curated App Shortcuts run, without storing secrets in Shortcuts.
public struct ManualRecipeCard: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let steps: [String]
    public let notes: String

    public static let all: [ManualRecipeCard] = [
        ManualRecipeCard(
            id: "import-export",
            title: "Import → Query → Transform → Export",
            steps: [
                "Open Shortcut Workbench (or Action Atlas) in Native Lab.",
                "Import or create the item this recipe should bind. The workbench stores its stable identifier, not its title.",
                "Run Find Lab Items with your query, or let the recipe resolve the bound identifier.",
                "Apply the transform (a note suffix in the demo recipe). The change leaves a receipt with an undo.",
                "Export the recipe. Secret-shaped fields appear only as [redacted].",
            ],
            notes: "Renaming the source item does not break the recipe. Cancelling during import discards the draft and writes nothing. Do not put passwords or API keys into Shortcuts Storage."
        ),
        ManualRecipeCard(
            id: "query-report",
            title: "Query → Report",
            steps: [
                "Open the Action Atlas action browser (the declared fallback).",
                "Run Find Lab Items with the text the recipe names.",
                "Inspect the optional model step in the workbench to see what would be sent, with secrets redacted.",
                "Export the recipe or the matching items.",
            ],
            notes: "The Action Atlas browser runs without Siri or Shortcuts. Curated App Shortcuts are a separate, smaller set."
        ),
    ]
}

/// Fallback copy that must match the experiment registration fallback verbatim for validators.
public enum WorkbenchFallback {
    public static let text = "Manual recipe instructions and app action browser; no secret storage inside Shortcuts."
}
