import Foundation
import LabDomain

/// The fixed rules for which doorway links this build accepts.
///
/// The https host is fictional (`*.example`) so the core build never needs public hosting. The
/// same path and parameter rules apply to App Clip activation URLs when that target is configured.
public enum DoorwayPolicy {
    /// Fictional https host used for universal-link shaped fixtures. Not a real site.
    public static let httpsHost = "doorway.nativelab.example"
    /// Host part of the `nativelab://` deep link.
    public static let deepLinkHost = "doorway"
    public static let deepLinkScheme = "nativelab"
    public static let httpsScheme = "https"

    /// The only action a link may request. Anything else is refused as privileged or unknown.
    public static let visitAction = "visit"
    /// Path that opens the local information page (no commit).
    public static let infoPath = "/info"
    /// Path prefix for the one scoped action: `/open/visit`.
    public static let openPrefix = "/open/"

    /// Query keys a visit link may carry. Any other key is refused.
    public static let allowedQueryKeys: Set<String> = ["item"]

    /// Query keys that look like an attempt to steer a privileged operation. Refused by name even
    /// if they somehow appeared on an otherwise allowed path.
    public static let privilegedQueryKeys: Set<String> = [
        "operation", "grant", "adapter", "authority", "actor", "request", "revision",
        "reset", "archive", "delete", "shell", "command",
    ]

    /// Path segments that must never run from a link.
    public static let privilegedPathSegments: Set<String> = [
        "reset-demo", "archive", "delete", "admin", "grant", "shell", "exec",
    ]

    /// Line appended to a demo sample's note when a visit is confirmed. Reset Demo restores the
    /// seed note; Reset Visits strips only this marker.
    public static let visitMarker = "Visited via Tiny Doorway."

    /// Demo sample IDs a visit link may name. Taken from `Fixtures/demo/seed.json`. A link that
    /// names any other UUID is refused before a store lookup, so it cannot probe user data.
    public static let allowedItemIDs: Set<ItemID> = Set(
        [
            "DB666EF1-F642-43F1-B415-895B6ECFF693", // Amber swatch
            "9B97BF2F-4D0B-4197-9CA8-36489DF40455", // Cobalt swatch
            "3A1711A8-E1DB-489E-8321-414266A8DF49", // Verdigris swatch
            "C8E1904C-E8DC-40A0-93D3-53F6C0FFF95D", // Ochre swatch
            "AF451890-CA80-4DE9-B18B-4007066C9177", // Quartz point
            "D279FB0E-642E-463A-B3DA-299442A1C7CB", // Banded agate slice
            "0FCB968F-7FEC-452A-A67C-20773B9C7761", // Pyrite cube
            "C6468C0B-4BF6-48E8-AE5D-F5FC7A041097", // Obsidian flake
            "8223D442-4B96-4026-B686-99CCFA09F1E8", // Cold-press sheet
            "6933AC83-9E61-4264-8EB8-0535B3C5E0F8", // Tracing vellum
            "6E2CED9D-B946-4188-8417-2E85C6A7268C", // Kraft card
            "E8E32999-AA3C-47C7-A530-2ABEE1EECC57", // Newsprint pad
        ].map { ItemID(rawValue: UUID(uuidString: $0)!) }
    )

    /// The primary fixture visit: Quartz point.
    public static let sampleItemID = ItemID(rawValue: UUID(uuidString: "AF451890-CA80-4DE9-B18B-4007066C9177")!)
    public static let sampleItemTitle = "Quartz point"
}
