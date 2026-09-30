import Foundation

/// The immutable value the app writes for the widget and the Control after each session change.
///
/// It holds only the running-or-paused state, the revision, when it was written, and, only when
/// the person chose to show details on surfaces, where and when the last change was made. It
/// holds no collection, item, note, receipt, or path. Surfaces read this file and nothing else:
/// they never open the store and never run a model.
public struct SessionSnapshot: Hashable, Sendable, Codable {
    public static let format = "native-lab-session-snapshot"
    public static let currentVersion = 1
    /// A snapshot is a few hundred bytes. Anything larger is refused before it is decoded.
    public static let maximumBytes = 2_048

    public let format: String
    public let formatVersion: Int
    public let state: SessionState
    public let writtenAt: Date
    /// Where and when the last change was made. `nil` unless the person turned on details for
    /// surfaces, so a snapshot is redacted by default.
    public let detail: SnapshotDetail?

    public init(state: SessionState, writtenAt: Date, detail: SnapshotDetail?) {
        format = Self.format
        formatVersion = Self.currentVersion
        self.state = state
        self.writtenAt = writtenAt
        self.detail = detail
    }

    public var isRedacted: Bool { detail == nil }

    /// Whether two snapshots would look different on a surface. The write time alone does not
    /// count, so rewriting the same state never asks WidgetKit for a reload.
    public func differs(from other: SessionSnapshot?) -> Bool {
        guard let other else { return true }
        return state != other.state || detail != other.detail
    }

    // MARK: Encoding

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }

    /// Decodes a snapshot, or `nil` when the bytes are too large, malformed, of another format,
    /// or from a newer build. A surface shows its placeholder for `nil`.
    public static func decode(_ data: Data) -> SessionSnapshot? {
        guard data.count <= maximumBytes else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(SessionSnapshot.self, from: data),
              snapshot.format == format,
              snapshot.formatVersion == currentVersion,
              snapshot.state.revision.map({ $0 >= 1 }) ?? true,
              snapshot.state.revision != nil || !snapshot.state.isRunning
        else { return nil }
        return snapshot
    }
}

/// The part of a snapshot that is private by default: where and when the last change was made.
public struct SnapshotDetail: Hashable, Sendable, Codable {
    public let changedFrom: SessionSurface
    public let changedAt: Date

    public init(changedFrom: SessionSurface, changedAt: Date) {
        self.changedFrom = changedFrom
        self.changedAt = changedAt
    }
}

/// What a surface found when it looked for the snapshot.
public enum SnapshotReading: Hashable, Sendable {
    case snapshot(SessionSnapshot)
    /// No snapshot yet: the app has not written one, or this build has no App Group.
    case missing
    /// A file is there but cannot be used: too large, malformed, a link, or from a newer build.
    case unreadable
}

/// The snapshot file inside the App Group container that the host variant and the widget
/// extension both declare. A CoreLocal build declares no App Group, so it has no file.
public struct SessionSnapshotFile: Sendable {
    /// The Info.plist key a SystemSurfaces bundle names its App Group in (the same key LAB-007
    /// uses). A CoreLocal build never declares it.
    public static let appGroupInfoKey = "LabAppGroupIdentifier"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The snapshot's place in an App Group container.
    public static func location(inGroupContainer container: URL) -> URL {
        container.appending(path: "Library/Application Support/Surface Deck/session-snapshot.json", directoryHint: .notDirectory)
    }

    /// The snapshot file for this bundle's App Group, or `nil` when the bundle declares none or
    /// the system gives no container for it (for example, a signature without the entitlement).
    public static func shared(for bundle: Bundle = .main) -> SessionSnapshotFile? {
        guard let value = bundle.object(forInfoDictionaryKey: appGroupInfoKey) as? String else { return nil }
        let group = value.trimmingCharacters(in: .whitespaces)
        guard !group.isEmpty, !group.contains("$("),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return SessionSnapshotFile(url: location(inGroupContainer: container))
    }

    /// Reads the snapshot. Never throws: every problem becomes `missing` or `unreadable`, which a
    /// surface shows as its placeholder.
    public func read() -> SnapshotReading {
        let path = url.path(percentEncoded: false)
        // The attributes of the path itself, not of what a link points to.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return FileManager.default.fileExists(atPath: path) ? .unreadable : .missing
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue, size <= SessionSnapshot.maximumBytes
        else { return .unreadable }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unreadable }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: SessionSnapshot.maximumBytes + 1),
              let snapshot = SessionSnapshot.decode(data)
        else { return .unreadable }
        return .snapshot(snapshot)
    }

    /// Replaces the snapshot in one atomic write. The file stays readable after first unlock,
    /// so a widget can draw it on the Lock Screen; it is redacted by default, and holds no content.
    public func write(_ snapshot: SessionSnapshot) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try snapshot.encoded().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
