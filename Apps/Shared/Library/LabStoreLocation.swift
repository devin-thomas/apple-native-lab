import Foundation

/// Where the host keeps its local store: one SQLite file in the app's own Application Support
/// folder. On the Mac the App Sandbox resolves that folder inside the app's container, so the
/// store never needs a file-access entitlement or a shared location.
enum LabStoreLocation {
    static let folderName = "Native Lab"
    static let fileName = "Lab.sqlite"

    /// A container-relative description that is safe to show; it never includes a user name.
    static let displayPath = "Application Support › \(folderName) › \(fileName)"

    /// The store file, creating its folder if needed. SQLite creates the file on first open.
    static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = support.appending(path: folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: fileName, directoryHint: .notDirectory)
    }
}
