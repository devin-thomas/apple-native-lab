import Darwin
import Foundation
import LabDomain

/// The origin records for one staging folder: one small file per staged import, named by its
/// staging ID, in a folder beside the staging area (never inside it, where CORE-006 refuses
/// any file a record does not list).
///
/// The first origin recorded for an ID wins, so sharing the same content again later does not
/// rewrite where it first came from. Files are created exclusively and read without following
/// links. A file that is missing, linked, oversized, or malformed reads as no origin.
public struct OriginLog: Sendable {
    public let root: URL
    /// Origins whose import is gone are removed once they are this old, so an interrupted
    /// intake cannot leave one behind for good.
    public static let orphanedAfter: TimeInterval = 60 * 60

    public init(root: URL) throws(ImportRejection) {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: Self.protection)
        } catch {
            throw .stagingUnavailable
        }
        var status = stat()
        guard lstat(Self.path(root), &status) == 0, status.st_mode & S_IFMT == S_IFDIR else { throw .linkedFileInStaging }
        self.root = root
    }

    /// Records `origin` unless one is already recorded for its import. Returns whether it wrote.
    @discardableResult
    public func record(_ origin: ImportOrigin) -> Bool {
        let descriptor = open(Self.path(file(for: origin.stagingID)), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return false }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: origin.encoded())
            try handle.synchronize()
            try handle.close()
            return true
        } catch {
            try? handle.close()
            remove(origin.stagingID)
            return false
        }
    }

    /// The recorded origin of one import, or `nil` if there is none or it does not validate.
    public func origin(for id: StagingID) -> ImportOrigin? {
        let descriptor = open(Self.path(file(for: id)), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1,
              status.st_size <= ImportOrigin.maximumBytes,
              let data = try? handle.read(upToCount: ImportOrigin.maximumBytes + 1)
        else { return nil }
        return ImportOrigin(decoding: data, expecting: id)
    }

    public func remove(_ id: StagingID) {
        unlink(Self.path(file(for: id)))
    }

    /// Removes origins for imports that are neither waiting nor set aside, once they are older
    /// than `orphanedAfter`, and any file that is not an origin at all.
    public func sweep(keeping live: Set<StagingID>, now: Date = Date()) {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: []
        )) ?? []
        let cutoff = now.addingTimeInterval(-Self.orphanedAfter)
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasSuffix(".json"), let uuid = UUID(uuidString: String(name.dropLast(5))),
                  uuid.uuidString + ".json" == name
            else {
                try? FileManager.default.removeItem(at: entry)
                continue
            }
            guard !live.contains(StagingID(rawValue: uuid)) else { continue }
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff { unlink(Self.path(entry)) }
        }
    }

    private func file(for id: StagingID) -> URL {
        root.appending(path: "\(id).json", directoryHint: .notDirectory)
    }

    private static func path(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static var protection: [FileAttributeKey: Any]? {
        #if os(macOS)
        nil
        #else
        [.protectionKey: FileProtectionType.completeUnlessOpen]
        #endif
    }
}
