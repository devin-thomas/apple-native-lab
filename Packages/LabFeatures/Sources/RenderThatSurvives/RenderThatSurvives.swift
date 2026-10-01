import Foundation

/// LAB-032 Render That Survives: a finite render that records itself as a job, so leaving the
/// screen, the app, or the process never turns it into a vanished spinner.
///
/// The render's frames are generated from a recipe; no source media is read. The module depends
/// on LabDomain and LabJobs. It imports AVFoundation, Core Image, and Metal, never the store, and
/// commits only through the host's `JobBackend`.
public enum RenderThatSurvives {
    public static let experimentID = "LAB-032"
    public static let title = "Render That Survives"
    public static let symbol = "film.stack"

    /// The bundled fixture recipes: a short one that renders as fast as it can, and a long one
    /// paced at playback speed so there is time to leave the app and come back.
    public static func bundledRecipes() throws(RecipeProblem) -> [RenderRecipe] {
        guard let url = Bundle.module.url(forResource: "recipes", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { throw .malformed }
        return try RenderRecipe.recipes(from: data)
    }
}
