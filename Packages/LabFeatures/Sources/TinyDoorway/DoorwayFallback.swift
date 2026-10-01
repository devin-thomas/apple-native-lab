import Foundation

/// Explained fallbacks when the App Clip path or the network is unavailable.
///
/// The core build never requires public hosting. The information page is local copy; the deep link
/// is an in-app `nativelab://` URL. Neither promises an App Store install.
public enum DoorwayFallback {
    /// Shown when an https doorway link is opened while offline.
    public static let offlineExplanation =
        "This device looks offline, so an https doorway link cannot reach an App Clip or a hosted page. Use the in-app deep link (nativelab://doorway/…) or read the local information page. Nothing was changed."

    /// Title of the local information page.
    public static let informationTitle = "Tiny Doorway"

    /// Body of the local information page. No network; no install promise.
    public static let informationBody = """
        Tiny Doorway opens one tightly scoped visit on a demo sample. A link is validated for host, path, and parameters before anything is offered, and confirming the visit still goes through the lab's ordinary authorization and receipt path.

        This build does not require a public website. The https links in the fixtures use a fictional example host so you can practice the same shape an App Clip or universal link would use after associated domains are configured.

        When the App Clip target is not set up, open a visit from a fixture or a nativelab:// deep link in the full app. Nothing here asks you to install anything.
        """

    /// One-line caption for the fallback section of the experiment UI.
    public static let caption =
        "Web information page or full-app deep link, with no forced installation promise."
}

/// Whether this build embeds a configured App Clip target.
///
/// App Clip invocation needs a FrontierOptional target, associated domains, and deployment
/// configuration. A custom URL scheme alone is not equivalent. CoreLocal always reports
/// `notConfigured` so the App Clip framework and entitlements never enter the default build.
public enum DoorwayClipStatus: Hashable, Sendable {
    case notConfigured(reason: String)
    /// Reserved for a FrontierOptional App Clip target after associated domains are set up.
    case configured

    /// This CoreLocal build has no App Clip target.
    public static let current: DoorwayClipStatus = .notConfigured(
        reason: "No App Clip target is embedded in this CoreLocal build. Associated domains and a FrontierOptional App Clip are required for clip invocation; until then use a fixture or the nativelab:// deep link in the full app."
    )

    public var explanation: String {
        switch self {
        case .notConfigured(let reason): reason
        case .configured: "An App Clip target is present in this build."
        }
    }
}
