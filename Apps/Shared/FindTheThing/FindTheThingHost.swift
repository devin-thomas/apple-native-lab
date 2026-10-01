import AppIntents
import FindTheThing

/// The one app index Find the Thing searches, and the link entity queries read.
enum FindTheThingHost {
    static let index = AppSearchIndex()

    /// Registers that index for app-entity queries. Call once at launch. It does not donate anything:
    /// donation is a separate action on the experiment's page.
    @MainActor
    static func connect() {
        AppDependencyManager.shared.add(dependency: FindTheThingLink(index: index))
    }
}
