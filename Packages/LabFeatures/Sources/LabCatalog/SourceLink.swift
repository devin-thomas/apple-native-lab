import Foundation

/// A file in the public repository: its path relative to the repository root, and the address of
/// that file on the public host. Opening the address is the reader's choice; the lab never fetches
/// it, so the path alone is enough to find the file offline in a checkout.
public struct SourceLink: Sendable, Hashable, Identifiable {
    /// The public repository's `main` branch. Only ever combined with a relative path from the
    /// generated catalog, never with anything read at run time.
    public static let repositoryBase = URL(string: "https://github.com/devin-thomas/apple-native-lab/blob/main/")!

    public let title: String
    public let relativePath: String

    public init(title: String, relativePath: String) {
        self.title = title
        self.relativePath = relativePath
    }

    public var id: String { relativePath }

    /// The file on the public host, or `nil` for a path that is not a plain relative path.
    public var url: URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains(".."),
              !relativePath.contains("://")
        else { return nil }
        return URL(string: relativePath, relativeTo: Self.repositoryBase)?.absoluteURL
    }
}
