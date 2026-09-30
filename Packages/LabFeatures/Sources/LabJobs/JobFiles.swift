import Foundation
import LabDomain

/// Reads how much space a volume has for a file the person asked for.
public protocol VolumeCapacityReading: Sendable {
    /// Bytes available at `url`, or `nil` when the system does not say.
    func availableBytes(at url: URL) throws -> Int64?
}

/// The system's reading: space for important, user-requested work, which counts space the system
/// can free by purging caches.
public struct LiveVolumeCapacity: VolumeCapacityReading {
    public init() {}

    public func availableBytes(at url: URL) throws -> Int64? {
        #if os(iOS) || os(macOS) || os(visionOS)
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return values.volumeAvailableCapacity.map(Int64.init)
        #else
        // watchOS and tvOS have no important-usage reading.
        return try url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity.map(Int64.init)
        #endif
    }
}

/// Why a destination folder cannot take a job's output. Each is checked before a job is created,
/// so a refusal records nothing.
public enum DestinationProblem: Error, Hashable, Sendable {
    /// The path exists and is not a folder, or it is a symbolic link.
    case notAFolder
    /// The folder cannot be created or written.
    case unwritable
    case insufficientSpace(needed: Int64, available: Int64)

    public var message: String {
        switch self {
        case .notAFolder:
            "The render folder is not a folder this app owns, so nothing was started."
        case .unwritable:
            "The render folder cannot be written, so nothing was started."
        case .insufficientSpace(let needed, let available):
            "This needs \(Self.bytes(needed)) free, and \(Self.bytes(available)) is available. Nothing was started."
        }
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

/// What a destination check found. `available` is `nil` when the system did not report capacity;
/// the job may then still run out of space and stop as `outOfSpace`.
public struct DestinationReport: Hashable, Sendable {
    public let needed: Int64
    public let available: Int64?
}

/// Checks file access and capacity for a job's folder before the job starts.
public struct DestinationCheck: Sendable {
    private let capacity: any VolumeCapacityReading

    public init(capacity: any VolumeCapacityReading = LiveVolumeCapacity()) {
        self.capacity = capacity
    }

    /// Creates `folder` if needed, proves it can be written by writing and removing a small probe
    /// file, and compares the volume's free space with `needed`.
    public func prepare(_ folder: URL, needing needed: Int64) throws(DestinationProblem) -> DestinationReport {
        let manager = FileManager.default
        if let values = try? folder.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) {
            guard values.isSymbolicLink != true, values.isDirectory == true else { throw .notAFolder }
        } else {
            do { try manager.createDirectory(at: folder, withIntermediateDirectories: true) } catch { throw .unwritable }
        }
        let probe = folder.appending(path: ".write-probe-\(UUID().uuidString)", directoryHint: .notDirectory)
        do {
            try Data().write(to: probe, options: .withoutOverwriting)
            try manager.removeItem(at: probe)
        } catch {
            try? manager.removeItem(at: probe)
            throw .unwritable
        }
        let available = try? capacity.availableBytes(at: folder)
        if let available, available < needed {
            throw .insufficientSpace(needed: needed, available: available)
        }
        return DestinationReport(needed: needed, available: available)
    }
}

/// Publishes a finished file over the previous one in a single rename.
///
/// The staged file must already be complete and on the destination's volume. `rename(2)` then
/// replaces the destination atomically: a reader, or a crash at any moment, sees either the whole
/// previous file or the whole new one, never a partial file. Nothing else writes the destination.
public enum AtomicPublication {
    public struct Published: Hashable, Sendable {
        public let digest: ContentDigest
        public let byteCount: Int64
    }

    public static func publish(_ staged: URL, to destination: URL) throws -> Published {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let status = staged.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else { return Int32(-1) }
                return rename(from, to)
            }
        }
        guard status == 0 else { throw CocoaError(.fileWriteUnknown) }
        return try digest(of: destination)
    }

    /// The SHA-256 and size of a file, read in chunks.
    public static func digest(of url: URL) throws -> Published {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = ContentHasher()
        var count: Int64 = 0
        while let chunk = try handle.read(upToCount: 1 << 16), !chunk.isEmpty {
            hasher.update(chunk)
            count += Int64(chunk.count)
        }
        return Published(digest: hasher.finalize(), byteCount: count)
    }
}
