import LabDomain

/// How an import entered the lab. Recorded with each staged import as provenance, and shown in
/// the inbox. It never selects an operation, an adapter, or a permission.
public enum IngressSurface: String, Hashable, Sendable, CaseIterable {
    /// The system share sheet, through the lab's share extension.
    case shareExtension = "share-extension"
    /// The host's Paste action.
    case paste
    /// The host's file picker.
    case filePicker = "file-picker"
    /// Files or content dropped on the host's inbox.
    case drop

    /// The name a person sees for this surface.
    public var title: String {
        switch self {
        case .shareExtension: "Share sheet"
        case .paste: "Paste"
        case .filePicker: "File picker"
        case .drop: "Drag and drop"
        }
    }
}

/// Which staging folder an import waits in, and so which adapter adopts it.
///
/// The folder is the trust boundary, not anything written inside it. Only the host can write to
/// its own container, so an import there came from the host's paste, file-picker, or drop
/// fallback and is adopted as the app UI. The App Group folder is written by the share
/// extension, so anything there arrived from another app and is adopted as the share extension,
/// whose ceiling excludes destructive changes (ADR-011) and whose every commit needs a grant
/// (ADR-013). An origin record in either folder is display data only.
public enum InboxSource: String, Hashable, Sendable, CaseIterable, Comparable {
    /// The host's own container.
    case host
    /// The App Group container the share extension writes. Only a SystemSurfaces build has one.
    case shareExtension = "share-extension"

    /// The adapter an adoption from this folder commits as.
    public var adapter: AdapterKind {
        switch self {
        case .host: .appUI
        case .shareExtension: .shareExtension
        }
    }

    /// Whether content that entered through `surface` belongs in this folder.
    public func accepts(_ surface: IngressSurface) -> Bool {
        switch self {
        case .host: surface != .shareExtension
        case .shareExtension: surface == .shareExtension
        }
    }

    public static func < (lhs: InboxSource, rhs: InboxSource) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
