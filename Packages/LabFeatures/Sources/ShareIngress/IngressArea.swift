import Foundation
import LabDomain
import LabStaging

/// One staging folder and its origin records: `<root>/staging` is a CORE-006 `StagingArea`,
/// and `<root>/origins` holds the `ImportOrigin` beside each staged import.
///
/// The host opens one for its own container. A SystemSurfaces build also opens one inside the
/// App Group container, the same folder the share extension opens, so the host reads what the
/// extension staged without the extension ever touching the store.
public struct IngressArea: Sendable {
    public let source: InboxSource
    public let staging: StagingArea
    public let origins: OriginLog

    /// The Info.plist key a SystemSurfaces host and its share extension name their App Group in.
    /// A CoreLocal build never declares it.
    public static let appGroupInfoKey = "LabAppGroupIdentifier"
    /// The experiment these imports belong to, for diagnostics.
    public static let subject = DiagnosticSubject("LAB-007")

    public init(source: InboxSource, root: URL, limits: ImportLimits = .standard, diagnostics: DiagnosticsLog? = nil) throws(ImportRejection) {
        self.source = source
        staging = try StagingArea(
            root: root.appending(path: "staging", directoryHint: .isDirectory),
            limits: limits, diagnostics: diagnostics, subject: Self.subject
        )
        origins = try OriginLog(root: root.appending(path: "origins", directoryHint: .isDirectory))
    }

    /// The folder for share-extension imports inside an App Group container.
    public static func shareExtensionRoot(inGroupContainer container: URL) -> URL {
        container.appending(path: "Library/Application Support/Share Inbox", directoryHint: .isDirectory)
    }

    /// The App Group this bundle declares for the share inbox, or `nil` when it declares none,
    /// or the value was never expanded from a build setting.
    public static func declaredAppGroup(in bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: appGroupInfoKey) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    /// The share-extension folder in this bundle's App Group container, or `nil` when the bundle
    /// declares no App Group or the system gives no container for it (for example, when the
    /// signature does not carry the entitlement).
    public static func shareExtensionRoot(for bundle: Bundle) -> URL? {
        guard let group = declaredAppGroup(in: bundle),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return shareExtensionRoot(inGroupContainer: container)
    }
}
