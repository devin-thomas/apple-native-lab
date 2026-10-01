import ActionAtlas
import AppIntents
import ContextCards
import LabDomain

/// Connects Context Cards to this host's store (LAB-002).
@MainActor
enum ContextCardsHost {
    /// The link the card publishes its visible sample to, and the link the Shortcut reads.
    /// `connect` replaces it before the system can run an intent.
    private(set) static var link = ContextCardsLink.unavailable

    /// Registers the link every Context Cards intent uses. Call once at launch, after Action Atlas
    /// is connected: both wrap this library, so a set-aside from the card and from a Shortcut land
    /// in the same receipt list.
    @MainActor
    static func connect(_ library: LabLibrary) {
        let link = ContextCardsLink(atlas: ActionAtlasLink(backend: LibraryAtlasBackend(library: library)))
        self.link = link
        AppDependencyManager.shared.add(dependency: link)
    }
}
