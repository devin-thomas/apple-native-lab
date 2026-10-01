#if canImport(AppIntents) && (os(iOS) || os(macOS))
import AppIntents

/// Lets the host include this module's visual-search intent in its App Intents metadata.
public struct PointInspectIntentsPackage: AppIntentsPackage {}
#endif

#if canImport(VisualIntelligence) && canImport(AppIntents) && (os(iOS) || os(macOS)) && compiler(>=6.4)
import AppIntents
import VisualIntelligence

/// The system's visual-search handoff into this lab.
///
/// The schema is `visualIntelligence.semanticContentSearch`. The descriptor also carries pixels;
/// this intent does not read them. It keeps the labels as an uncertain suggestion and opens the
/// app so a person can edit and apply that suggestion. It does not commit, and it does not run
/// anything the labels say.
@available(iOS 26.0, macOS 27.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@AppIntent(schema: .visualIntelligence.semanticContentSearch)
struct PointInspectVisualSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Review Visual Search in Native Lab"
    static let description = IntentDescription(
        "Turns system visual-search labels into an editable suggestion. Nothing is saved until you apply it."
    )
    static let openAppWhenRun = true

    @Parameter
    var semanticContent: SemanticContentDescriptor

    func perform() async throws -> some IntentResult {
        let observation = VisualSearchParticipation.observation(labels: semanticContent.labels)
        await VisualSearchHandoff.shared.store(observation)
        return .result()
    }
}
#endif
