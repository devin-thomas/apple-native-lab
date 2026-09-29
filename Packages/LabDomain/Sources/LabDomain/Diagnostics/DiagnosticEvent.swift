import Foundation

/// A fixed name in a diagnostic event: a phase such as `import.stage`, or a count such as `files`.
///
/// It can be made only from a string literal, so runtime text (a filename, a prompt, a token, a
/// person's note) can never become part of an event. Valid names use lowercase ASCII letters,
/// digits, `.`, `-`, and `_`, and have at most 48 characters. A literal outside that set is
/// replaced character by character with `_` (and asserts in debug builds), so a typo cannot
/// crash a release build or smuggle text into a log.
public struct DiagnosticName: Hashable, Sendable, Comparable, Encodable, CustomStringConvertible, ExpressibleByStringLiteral {
    public static let maximumLength = 48

    public let rawValue: String

    /// Only a literal can be a name: the literal type is `StaticString`, and there is no
    /// interpolation, so `"file \(name)"` does not compile as a `DiagnosticName`.
    public init(stringLiteral literal: StaticString) {
        self.init(literal)
    }

    public init(_ literal: StaticString) {
        let text = literal.description
        assert(Self.isValid(text), "Diagnostic names use lowercase letters, digits, '.', '-', and '_'.")
        let scalars = text.unicodeScalars.prefix(Self.maximumLength).map { Self.isAllowed($0) ? Character($0) : "_" }
        rawValue = scalars.isEmpty ? "_" : String(scalars)
    }

    static func isValid(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.count <= maximumLength && text.unicodeScalars.allSatisfy(isAllowed)
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "0"..."9", ".", "-", "_": true
        default: false
        }
    }

    public var description: String { rawValue }

    public static func < (lhs: DiagnosticName, rhs: DiagnosticName) -> Bool { lhs.rawValue < rhs.rawValue }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The ticket or experiment an event belongs to, such as `LAB-007`, `LAB-007-A`, or `CORE-006`.
///
/// Only that shape is accepted: uppercase ASCII letters, a hyphen, three digits, and an optional
/// hyphen and part letter. Anything else, including free text, is refused.
public struct DiagnosticSubject: Hashable, Sendable, Encodable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ value: String) {
        guard Self.isValid(value) else { return nil }
        rawValue = value
    }

    static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return false }
        let prefix = parts[0].count <= 8 && !parts[0].isEmpty && parts[0].allSatisfy { $0.isASCII && $0.isUppercase }
        let number = parts[1].count == 3 && parts[1].allSatisfy { $0.isASCII && $0.isNumber }
        let part = parts.count == 2 || (parts[2].count == 1 && parts[2].allSatisfy { $0.isASCII && $0.isUppercase })
        return prefix && number && part
    }

    public var description: String { rawValue }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// How a diagnosed step ended.
public enum DiagnosticOutcome: String, Hashable, Sendable, Encodable, CaseIterable {
    case started
    case succeeded
    /// The input or request was refused, as designed: hostile or invalid input, a missing grant.
    case rejected
    /// Something that should have worked did not, such as storage.
    case failed
    case cancelled
}

/// Why a step was rejected or failed, as a category only. Never a message, a path, or content.
public enum DiagnosticCategory: String, Hashable, Sendable, Encodable, CaseIterable {
    case invalidInput = "invalid-input"
    case tooLarge = "too-large"
    case unsafePath = "unsafe-path"
    case unsafeArchive = "unsafe-archive"
    case malformedData = "malformed-data"
    case tamperedStaging = "tampered-staging"
    case duplicate
    case unauthorized
    case grantMissing = "grant-missing"
    case grantExpired = "grant-expired"
    case grantOutOfScope = "grant-out-of-scope"
    case conflict
    case notFound = "not-found"
    case unsupported
    case unavailable
    case storeFailure = "store-failure"
    case cancelled
    case other

    /// The outcome an error of this category implies.
    public var outcome: DiagnosticOutcome {
        switch self {
        case .cancelled: .cancelled
        case .unavailable, .storeFailure, .other: .failed
        default: .rejected
        }
    }

    /// Classifies an error by its type and case alone. It never reads the error's description,
    /// which for system errors often contains file paths or content.
    public init(classifying error: any Error) {
        switch error {
        case let rejection as ImportRejection: self = rejection.category
        case let grantError as GrantError: self = grantError.category
        case let operationError as OperationError: self = operationError.diagnosticCategory
        case is ValidationError: self = .invalidInput
        case is CancellationError: self = .cancelled
        default: self = .other
        }
    }
}

/// One named count in an event, such as `files = 3`.
public struct DiagnosticCount: Hashable, Sendable, Encodable {
    public let name: DiagnosticName
    public let value: Int

    public init(_ name: DiagnosticName, _ value: Int) {
        self.name = name
        self.value = value
    }
}

/// One metadata-only diagnostic record.
///
/// Every field is a fixed name, a validated ticket or experiment ID, a closed set of values, a
/// number, or a time rounded to the second. There is no field that can hold free text, so an
/// event cannot carry a prompt, a transcript, a filename, a path, a token, or personal content
/// (docs/SECURITY_AND_PRIVACY.md). It is `Encodable` but deliberately not `Decodable`: nothing
/// read from outside the process can become an event.
public struct DiagnosticEvent: Hashable, Sendable, Encodable {
    /// Increases by one for each event recorded in one log.
    public let sequence: Int
    public let recordedAt: Date
    public let subject: DiagnosticSubject?
    public let phase: DiagnosticName
    public let outcome: DiagnosticOutcome
    public let category: DiagnosticCategory?
    /// Whole milliseconds.
    public let durationMilliseconds: Int?
    /// Sorted by name, each name once.
    public let counts: [DiagnosticCount]

    init(
        sequence: Int,
        recordedAt: Date,
        subject: DiagnosticSubject?,
        phase: DiagnosticName,
        outcome: DiagnosticOutcome,
        category: DiagnosticCategory?,
        duration: Duration?,
        counts: [DiagnosticName: Int]
    ) {
        self.sequence = sequence
        self.recordedAt = Date(timeIntervalSince1970: recordedAt.timeIntervalSince1970.rounded(.down))
        self.subject = subject
        self.phase = phase
        self.outcome = outcome
        self.category = category
        durationMilliseconds = duration.map { Int($0.components.seconds) * 1_000 + Int($0.components.attoseconds / 1_000_000_000_000_000) }
        self.counts = counts.map { DiagnosticCount($0.key, $0.value) }.sorted { $0.name < $1.name }
    }

    /// The single line the default log sinks write, for example
    /// `phase=import.stage outcome=rejected category=unsafe-path subject=LAB-007 ms=4 files=2`.
    public var line: String {
        var fields = ["phase=\(phase)", "outcome=\(outcome.rawValue)"]
        if let category { fields.append("category=\(category.rawValue)") }
        if let subject { fields.append("subject=\(subject)") }
        if let durationMilliseconds { fields.append("ms=\(durationMilliseconds)") }
        fields += counts.map { "\($0.name)=\($0.value)" }
        return fields.joined(separator: " ")
    }
}

extension OperationError {
    var diagnosticCategory: DiagnosticCategory {
        switch self {
        case .invalidPayload: .invalidInput
        case .unauthorized: .unauthorized
        case .notFound: .notFound
        case .requestIDReused: .duplicate
        case .ruleViolation(.alreadyExists): .duplicate
        case .ruleViolation: .invalidInput
        case .storeFailure: .storeFailure
        }
    }
}
