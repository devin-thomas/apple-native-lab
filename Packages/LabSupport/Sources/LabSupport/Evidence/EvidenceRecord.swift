import Foundation

/// One observed check, recorded so a claim can be traced to the run that supports it
/// (docs/EVIDENCE_TEMPLATE.md).
///
/// A record states what it can support rather than choosing: `supportedState` follows from the
/// result and execution path alone. Every initializer validates, including decoding, so a record
/// in memory always has a known subject, a non-blank outcome detail, and device facts only when
/// its path is physical.
public struct EvidenceRecord: Sendable, Equatable {
    /// The JSON layout version. Decoding refuses any other.
    public static let schemaVersion = 1

    /// The ticket or experiment the check belongs to, such as "CORE-007", "LAB-001", or "LAB-001-B".
    public let subject: String
    /// What was checked, in a few words.
    public let check: String
    /// When the check ran, to the second.
    public let date: Date
    /// The source revision and toolchain that produced what was checked.
    public let provenance: BuildProvenance
    /// Where the check ran.
    public let execution: Execution
    /// The input and fixture identifiers used, ideally with a content hash.
    public let inputs: [String]
    /// The reproducible commands or manual steps.
    public let steps: [String]
    /// The result with what was observed, or why the check did not run.
    public let outcome: RunOutcome
    /// Untested platforms, simulations, and uncertain results.
    public let limitations: [String]

    public init(
        subject: String,
        check: String,
        date: Date,
        provenance: BuildProvenance,
        execution: Execution,
        inputs: [String] = [],
        steps: [String] = [],
        outcome: RunOutcome,
        limitations: [String] = []
    ) throws {
        guard Self.isValidSubject(subject) else { throw EvidenceError.invalidSubject(subject) }
        guard !check.isBlank else { throw EvidenceError.blankField("check") }
        guard !outcome.detail.isBlank else { throw EvidenceError.blankField("outcome.detail") }
        for (field, values) in [("inputs", inputs), ("steps", steps), ("limitations", limitations)]
        where values.contains(where: \.isBlank) {
            throw EvidenceError.blankField(field)
        }
        self.subject = subject
        self.check = check
        self.date = EvidenceDate.normalized(date)
        self.provenance = provenance
        self.execution = execution
        self.inputs = inputs
        self.steps = steps
        self.outcome = outcome
        self.limitations = limitations
    }

    public var path: ExecutionPath { execution.path }
    public var result: RunResult { outcome.result }

    /// The highest implementation state this record alone can support, or `nil` when it did not
    /// pass. A simulator or fixture record never supports `device-verified`.
    public var supportedState: ImplementationState? {
        result.isPassed ? path.highestSupportedState : nil
    }

    /// A row for the evidence log in docs/BUILD_STATUS.md: date, check, command, result.
    ///
    /// The result cell leads with this record's own result and path, so a blocked or not-run
    /// check can never read as passed.
    public var logRow: String {
        let steps = steps.isEmpty ? "none" : steps.map(Self.codeSpan).joined(separator: "; ")
        var result = "\(outcome.result.title) (\(execution.summary)): \(outcome.detail)"
        if !limitations.isEmpty {
            result += ". Limitations: " + limitations.joined(separator: "; ")
        }
        let cells = [EvidenceDate.day(date), "\(check) (\(subject))", steps, result]
        return "| " + cells.map(Self.tableCell).joined(separator: " | ") + " |"
    }

    /// Ticket and experiment IDs: uppercase letters, a hyphen, three digits, and an optional
    /// hyphen and part letter, such as "CORE-007", "LAB-001", or "LAB-001-B".
    static func isValidSubject(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return false }
        let prefixOK = !parts[0].isEmpty && parts[0].allSatisfy { $0.isASCII && $0.isUppercase }
        let numberOK = parts[1].count == 3 && parts[1].allSatisfy { $0.isASCII && $0.isNumber }
        let partOK = parts.count == 2 || (parts[2].count == 1 && parts[2].allSatisfy { $0.isASCII && $0.isUppercase })
        return prefixOK && numberOK && partOK
    }

    private static func codeSpan(_ text: String) -> String {
        text.contains("`") ? text : "`\(text)`"
    }

    private static func tableCell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .components(separatedBy: .newlines)
            .joined(separator: " ")
    }
}

extension EvidenceRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case subject
        case check
        case date
        case provenance
        case execution
        case inputs
        case steps
        case outcome
        case limitations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container,
                debugDescription: EvidenceError.unsupportedSchemaVersion(version).description
            )
        }
        let dateText = try container.decode(String.self, forKey: .date)
        guard let date = EvidenceDate.parse(dateText) else {
            throw DecodingError.dataCorruptedError(
                forKey: .date, in: container, debugDescription: "Expected an ISO 8601 date and time, such as 2026-09-29T12:00:00Z."
            )
        }
        do {
            try self.init(
                subject: try container.decode(String.self, forKey: .subject),
                check: try container.decode(String.self, forKey: .check),
                date: date,
                provenance: try container.decode(BuildProvenance.self, forKey: .provenance),
                execution: try container.decode(Execution.self, forKey: .execution),
                inputs: try container.decode([String].self, forKey: .inputs),
                steps: try container.decode([String].self, forKey: .steps),
                outcome: try container.decode(RunOutcome.self, forKey: .outcome),
                limitations: try container.decode([String].self, forKey: .limitations)
            )
        } catch let error as EvidenceError {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: error.description))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(subject, forKey: .subject)
        try container.encode(check, forKey: .check)
        try container.encode(EvidenceDate.format(date), forKey: .date)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(execution, forKey: .execution)
        try container.encode(inputs, forKey: .inputs)
        try container.encode(steps, forKey: .steps)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(limitations, forKey: .limitations)
    }
}

/// Why an evidence record, or part of one, could not be created.
public enum EvidenceError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The subject is not a ticket or experiment ID.
    case invalidSubject(String)
    /// A required text field, or an entry in a list, is empty.
    case blankField(String)
    /// A device field looks like a serial number or device identifier. The value is not repeated.
    case deviceIdentifier(field: String)
    /// A device snapshot named a platform the lab does not know.
    case unknownPlatform(String)
    /// The JSON was written with a layout this build does not read.
    case unsupportedSchemaVersion(Int)

    public var description: String {
        switch self {
        case .invalidSubject(let value):
            "\"\(value)\" is not a ticket or experiment ID such as CORE-007 or LAB-001-B."
        case .blankField(let field):
            "\(field) must not be empty."
        case .deviceIdentifier(let field):
            "\(field) looks like a serial number or device identifier. Record the device class and OS only."
        case .unknownPlatform(let platform):
            "\"\(platform)\" is not a lab platform."
        case .unsupportedSchemaVersion(let version):
            "Evidence schema version \(version) is not supported; expected \(EvidenceRecord.schemaVersion)."
        }
    }
}

/// Evidence dates: whole seconds, written as ISO 8601 in UTC whatever the encoder's settings.
enum EvidenceDate {
    static func normalized(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    static func format(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }

    static func parse(_ text: String) -> Date? {
        try? Date.ISO8601FormatStyle().parse(text)
    }

    /// The UTC day, such as "2026-09-29".
    static func day(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle().year().month().day())
    }
}
