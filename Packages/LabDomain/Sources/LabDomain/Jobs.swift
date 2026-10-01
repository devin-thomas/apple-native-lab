import Foundation

/// What kind of long-running work a job is, such as `render` (LAB-032 Render That Survives).
///
/// Each experiment that runs finite, expensive work names its own kind, so one job model serves
/// renders, exports, reconstructions, and recordings. A kind is a short lowercase slug: letters,
/// digits, and single hyphens between them.
public struct JobKind: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public static let maximumLength = 40

    /// LAB-032 Render That Survives.
    public static let render = JobKind(unchecked: "render")

    public let rawValue: String

    /// `nil` unless `rawValue` is a slug of at most 40 characters.
    public init?(rawValue: String) {
        guard Slug.isValid(rawValue, maximumLength: Self.maximumLength) else { return nil }
        self.rawValue = rawValue
    }

    private init(unchecked value: String) { rawValue = value }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let kind = JobKind(rawValue: try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "A job kind is a lowercase slug.")
        }
        self = kind
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// How far a job has come, in units the job defines, such as segments of a render.
///
/// `completed` counts units whose work is durable: a job that stops keeps them and resumes after
/// them. `total` is `nil` when the amount of work is not known, and a presentation then shows
/// indeterminate progress rather than a made-up percentage.
public struct JobProgress: Hashable, Sendable, Codable {
    public static let maximumUnits = 1_000_000

    public let completed: Int
    public let total: Int?

    public init(completed: Int, total: Int?) throws(ValidationError) {
        guard completed >= 0, completed <= Self.maximumUnits else { throw .progressOutOfRange }
        if let total {
            guard total >= 1, total <= Self.maximumUnits, completed <= total else { throw .progressOutOfRange }
        }
        self.completed = completed
        self.total = total
    }

    /// The share of the work that is durable, or `nil` when the total is unknown.
    public var fraction: Double? {
        total.map { Double(completed) / Double($0) }
    }

    /// "3 of 5", or "3" when the total is unknown.
    public var phrase: String {
        total.map { "\(completed) of \($0)" } ?? "\(completed)"
    }

    private enum CodingKeys: String, CodingKey {
        case completed, total
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            completed: container.decode(Int.self, forKey: .completed),
            total: container.decodeIfPresent(Int.self, forKey: .total)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(completed, forKey: .completed)
        try container.encodeIfPresent(total, forKey: .total)
    }
}

/// Why a job stopped before it finished. An interrupted job keeps its durable progress and can
/// resume; nothing here is a failure.
public enum JobInterruption: String, Hashable, Sendable, Codable, CaseIterable {
    /// The job was still marked running when the app started again: the app stopped, or was
    /// stopped, while the job ran.
    case appStopped = "app-stopped"
    /// The system ended the time it allowed the job in the background.
    case expired
    /// The app left the foreground and the job had no permission to continue there.
    case leftForeground = "left-foreground"
    /// A person paused it.
    case paused
    /// The destination ran out of space.
    case outOfSpace = "out-of-space"

    /// The clause a receipt uses after "because".
    public var clause: String {
        switch self {
        case .appStopped: "the app stopped while it ran"
        case .expired: "its time in the background ran out"
        case .leftForeground: "the app left the foreground"
        case .paused: "it was paused"
        case .outOfSpace: "the destination ran out of space"
        }
    }
}

/// Why a job ended without a result. `code` is a slug for tests and logs; `message` is one
/// sentence for a person. Neither may hold a path or content.
public struct JobFailure: Hashable, Sendable, Codable {
    public static let maximumMessageLength = 300

    public let code: String
    public let message: String

    public init(code: String, message: String) throws(ValidationError) {
        guard Slug.isValid(code, maximumLength: JobKind.maximumLength) else { throw .invalidSlug(in: .failureCode) }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= Self.maximumMessageLength else { throw .textLength(in: .failureMessage) }
        guard !trimmed.containsControlCharacter() else { throw .controlCharacter(in: .failureMessage) }
        self.code = code
        self.message = trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case code, message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(code: container.decode(String.self, forKey: .code), message: container.decode(String.self, forKey: .message))
    }
}

/// The result a finished job published: a file name inside the job's own destination, never a
/// path, with its size, its SHA-256, and a one-line description.
public struct JobOutput: Hashable, Sendable, Codable {
    public static let maximumNameLength = 120
    public static let maximumSummaryLength = 200

    public let name: String
    public let byteCount: Int64
    /// 64 lowercase hexadecimal characters.
    public let sha256: String
    public let summary: String

    public init(name: String, byteCount: Int64, sha256: String, summary: String) throws(ValidationError) {
        guard Self.isSafeName(name) else { throw .unsafeFileName }
        guard byteCount >= 0 else { throw .negativeByteCount }
        guard ContentDigest(hex: sha256) != nil else { throw .invalidDigest }
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= Self.maximumSummaryLength else { throw .textLength(in: .outputSummary) }
        guard !trimmed.containsControlCharacter() else { throw .controlCharacter(in: .outputSummary) }
        self.name = name
        self.byteCount = byteCount
        self.sha256 = sha256
        self.summary = trimmed
    }

    /// One file name: no folder separators, no leading dot, no control characters, and not
    /// empty, "." or "..".
    public static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= maximumNameLength && !name.hasPrefix(".")
            && !name.contains("/") && !name.contains(":") && !name.contains("\\")
            && !name.containsControlCharacter()
            && name.trimmingCharacters(in: .whitespaces) == name
    }

    private enum CodingKeys: String, CodingKey {
        case name, byteCount, sha256, summary
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decode(String.self, forKey: .name),
            byteCount: container.decode(Int64.self, forKey: .byteCount),
            sha256: container.decode(String.self, forKey: .sha256),
            summary: container.decode(String.self, forKey: .summary)
        )
    }
}

/// Where a job is in its lifecycle. `running` and `interrupted` can still change; the other three
/// are final.
public enum JobPhase: Hashable, Sendable, Codable {
    case running
    /// Stopped with its durable progress kept. It can resume or be cancelled.
    case interrupted(reason: JobInterruption)
    case succeeded(output: JobOutput)
    case failed(failure: JobFailure)
    case cancelled

    public enum Name: String, Hashable, Sendable, Codable, CaseIterable {
        case running, interrupted, succeeded, failed, cancelled
    }

    public var name: Name {
        switch self {
        case .running: .running
        case .interrupted: .interrupted
        case .succeeded: .succeeded
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }

    /// Whether the job has ended. A finished job never changes again.
    public var isFinished: Bool {
        switch self {
        case .running, .interrupted: false
        case .succeeded, .failed, .cancelled: true
        }
    }
}

/// One finite piece of expensive work that a person started, such as a render (LAB-032).
///
/// A job records the truth about work the app does outside a single call: that it is running,
/// how much of it is durable, why it stopped, and how it ended. The work itself, and any files,
/// belong to the experiment that runs it. Every change is a `DomainOperation` through
/// `OperationService`, so it is authorized and leaves a receipt, and a surface that shows a job
/// after a relaunch shows what the store holds rather than a spinner that vanished.
///
/// A job's kind, title, and namespace never change. Its progress only moves forward, and a
/// finished job never changes again. No change to a job is undoable: its effects are files and
/// time, which a receipt cannot take back.
public struct LabJob: DomainEntity, Identifiable {
    public static let kind = EntityKind.job

    public let id: JobID
    public let jobKind: JobKind
    public let title: EntityTitle
    public let phase: JobPhase
    public let progress: JobProgress
    public let revision: Revision
    /// Demo jobs run on fixtures and Reset Demo removes them; user jobs are never removed.
    public let namespace: DataNamespace

    public init(
        id: JobID,
        jobKind: JobKind,
        title: EntityTitle,
        phase: JobPhase = .running,
        progress: JobProgress,
        revision: Revision = .initial,
        namespace: DataNamespace = .demo
    ) {
        self.id = id
        self.jobKind = jobKind
        self.title = title
        self.phase = phase
        self.progress = progress
        self.revision = revision
        self.namespace = namespace
    }

    public var reference: EntityReference { .job(id) }

    /// The next revision in the given phase and progress.
    func revised(phase: JobPhase, progress: JobProgress? = nil) -> LabJob {
        LabJob(
            id: id, jobKind: jobKind, title: title, phase: phase, progress: progress ?? self.progress,
            revision: revision.next(), namespace: namespace
        )
    }
}

/// The content of a new job. The caller chooses the ID, so a retry names the same job.
public struct JobDraft: Hashable, Sendable, Codable {
    public let id: JobID
    public let kind: JobKind
    public let title: EntityTitle
    /// The number of units the job will complete, or `nil` when it is not known.
    public let total: Int?
    public let namespace: DataNamespace

    public init(
        id: JobID = JobID(),
        kind: JobKind,
        title: EntityTitle,
        total: Int?,
        namespace: DataNamespace = .demo
    ) throws(ValidationError) {
        _ = try JobProgress(completed: 0, total: total)
        self.id = id
        self.kind = kind
        self.title = title
        self.total = total
        self.namespace = namespace
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, total, namespace
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(JobID.self, forKey: .id),
            kind: container.decode(JobKind.self, forKey: .kind),
            title: container.decode(EntityTitle.self, forKey: .title),
            total: container.decodeIfPresent(Int.self, forKey: .total),
            namespace: container.decode(DataNamespace.self, forKey: .namespace)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(total, forKey: .total)
        try container.encode(namespace, forKey: .namespace)
    }
}

/// One step in a job's lifecycle, as `DomainOperation.updateJob` carries it.
///
/// | Transition   | Allowed from           | Result |
/// |--------------|------------------------|--------|
/// | `checkpoint` | running                | running, with more durable units |
/// | `interrupt`  | running                | interrupted, progress kept |
/// | `resume`     | interrupted            | running, progress kept |
/// | `cancel`     | running or interrupted | cancelled (final) |
/// | `fail`       | running or interrupted | failed (final) |
/// | `succeed`    | running                | succeeded (final), progress complete |
public enum JobTransition: Hashable, Sendable, Codable {
    /// Records that `completed` units are durable. It must move forward and stay within the total.
    case checkpoint(completed: Int)
    case interrupt(reason: JobInterruption)
    case resume
    case cancel
    case fail(failure: JobFailure)
    case succeed(output: JobOutput)
}

enum Slug {
    /// Lowercase ASCII letters and digits, with single hyphens between them.
    static func isValid(_ value: String, maximumLength: Int) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= maximumLength, bytes.first != 0x2D, bytes.last != 0x2D else { return false }
        var previousWasHyphen = false
        for byte in bytes {
            let isHyphen = byte == 0x2D
            guard isHyphen || (0x61...0x7A).contains(byte) || (0x30...0x39).contains(byte) else { return false }
            if isHyphen && previousWasHyphen { return false }
            previousWasHyphen = isHyphen
        }
        return true
    }
}
