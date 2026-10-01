import Foundation

/// Where to come back to: a clip, a position, and the captions. It names the clip by its lab ID,
/// never by a path or URL, and holds nothing a person wrote.
public struct ResumePoint: Hashable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let clip: MediaAssetID
    public let position: Double
    public let caption: CaptionChoice

    public init(clip: MediaAssetID, position: Double, caption: CaptionChoice) {
        schemaVersion = Self.currentSchemaVersion
        self.clip = clip
        self.position = position
        self.caption = caption
    }
}

/// What reading a saved resume point found.
public enum ResumePointLoad: Hashable, Sendable {
    case none
    case found(ResumePoint)
    /// A file was there but is not a resume point this build accepts. It was ignored and left in
    /// place; the next save replaces it, and Reset removes it.
    case discarded(reason: String)
}

/// Keeps the one resume point the experiment owns. Reset removes it and nothing else.
public protocol ResumePointStore: Sendable {
    func load() -> ResumePointLoad
    func save(_ point: ResumePoint) throws
    func remove() throws
}

/// The resume point as one small JSON file in a folder the host chooses, such as the app's
/// Application Support folder. The folder holds nothing else of the lab's.
public struct FileResumePointStore: ResumePointStore {
    public static let fileName = "screening-room-resume-point.json"
    /// Larger than any real resume point; a larger file is refused before it is decoded.
    static let maximumBytes = 4096

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public var file: URL { folder.appendingPathComponent(Self.fileName, isDirectory: false) }

    public func load() -> ResumePointLoad {
        let data: Data
        do {
            let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
            guard size <= Self.maximumBytes else { return .discarded(reason: "The saved resume point is too large to be one.") }
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .none
        } catch {
            return .discarded(reason: "The saved resume point could not be read.")
        }
        guard let point = try? JSONDecoder().decode(ResumePoint.self, from: data) else {
            return .discarded(reason: "The saved resume point is not in a form this build reads.")
        }
        guard point.schemaVersion == ResumePoint.currentSchemaVersion else {
            return .discarded(reason: "The saved resume point is from a different version (\(point.schemaVersion)).")
        }
        guard point.position.isFinite, point.position >= 0 else {
            return .discarded(reason: "The saved resume point has no valid position.")
        }
        guard let clip = ScreeningClips.clip(point.clip), clip.expectation == .plays else {
            return .discarded(reason: "The saved resume point names a clip this build cannot play.")
        }
        return .found(point)
    }

    public func save(_ point: ResumePoint) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(point).write(to: file, options: .atomic)
    }

    public func remove() throws {
        do {
            try FileManager.default.removeItem(at: file)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}

/// A resume point kept in memory, for tests and for a host that cannot write files.
public final class MemoryResumePointStore: ResumePointStore, @unchecked Sendable {
    private let lock = NSLock()
    private var point: ResumePoint?

    public init(_ point: ResumePoint? = nil) {
        self.point = point
    }

    public func load() -> ResumePointLoad {
        lock.withLock { point.map(ResumePointLoad.found) ?? .none }
    }

    public func save(_ point: ResumePoint) throws {
        lock.withLock { self.point = point }
    }

    public func remove() throws {
        lock.withLock { point = nil }
    }
}
