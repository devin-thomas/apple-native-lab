import Foundation

/// What a person chose to include in a diagnostics export.
public struct DiagnosticExportSelection: Hashable, Sendable {
    /// Only events for these tickets or experiments, or every event when `nil`.
    public var subjects: Set<DiagnosticSubject>?
    /// Only events with these outcomes, or every outcome when `nil`.
    public var outcomes: Set<DiagnosticOutcome>?
    public var includeDurations: Bool
    public var includeCounts: Bool

    public init(
        subjects: Set<DiagnosticSubject>? = nil,
        outcomes: Set<DiagnosticOutcome>? = nil,
        includeDurations: Bool = true,
        includeCounts: Bool = true
    ) {
        self.subjects = subjects
        self.outcomes = outcomes
        self.includeDurations = includeDurations
        self.includeCounts = includeCounts
    }

    public static let everything = DiagnosticExportSelection()

    func includes(_ event: DiagnosticEvent) -> Bool {
        if let subjects, !(event.subject.map(subjects.contains) ?? false) { return false }
        if let outcomes, !outcomes.contains(event.outcome) { return false }
        return true
    }
}

/// Exactly what a diagnostics export will write, computed before the person picks a destination.
///
/// `text` is the complete export, and `data` is its UTF-8 bytes; `write(to:)` writes those bytes
/// and nothing else, so the preview a person reviews is the file they share. The export is
/// redacted beyond the events themselves: times are rounded down to the minute, sequence numbers
/// are dropped, and durations or counts are omitted when the selection says so. It holds no
/// device name, account, path, filename, or content, and it is JSON with no embedded metadata.
public struct DiagnosticExportPreview: Hashable, Sendable {
    public static let format = "native-lab-diagnostics"
    public static let formatVersion = 1
    public static let suggestedFileName = "native-lab-diagnostics.json"

    /// What the export contains and leaves out, for the preview screen.
    public static let redactionNotes = [
        "Contains only ticket or experiment IDs, phases, outcomes, error categories, durations, and counts.",
        "Contains no prompts, transcripts, file names, paths, tokens, or personal content.",
        "Times are rounded down to the minute.",
        "Nothing is sent anywhere; you choose where the file is saved.",
    ]

    public let text: String
    public let includedEventCount: Int
    public let excludedEventCount: Int

    public var data: Data { Data(text.utf8) }

    init(events: [DiagnosticEvent], selection: DiagnosticExportSelection) {
        let included = events.filter(selection.includes)
        let document = ExportDocument(
            format: Self.format,
            formatVersion: Self.formatVersion,
            events: included.map { ExportedEvent($0, selection: selection) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        // Every field is a fixed name, a validated ID, an enum, a number, or a date, so encoding
        // cannot fail; an empty export is still a valid document if it somehow did.
        let encoded = (try? encoder.encode(document)) ?? Data("{}".utf8)
        text = String(decoding: encoded, as: UTF8.self) + "\n"
        includedEventCount = included.count
        excludedEventCount = events.count - included.count
    }

    /// Writes exactly `data` to a new file at a location the person chose. It never replaces a
    /// file that already exists there.
    public func write(to url: URL) throws {
        try data.write(to: url, options: [.withoutOverwriting])
    }
}

private struct ExportDocument: Encodable {
    let format: String
    let formatVersion: Int
    let events: [ExportedEvent]
}

private struct ExportedEvent: Encodable {
    let recordedAt: Date
    let subject: DiagnosticSubject?
    let phase: DiagnosticName
    let outcome: DiagnosticOutcome
    let category: DiagnosticCategory?
    let durationMilliseconds: Int?
    let counts: [String: Int]?

    init(_ event: DiagnosticEvent, selection: DiagnosticExportSelection) {
        let seconds = event.recordedAt.timeIntervalSince1970
        recordedAt = Date(timeIntervalSince1970: seconds - seconds.truncatingRemainder(dividingBy: 60))
        subject = event.subject
        phase = event.phase
        outcome = event.outcome
        category = event.category
        durationMilliseconds = selection.includeDurations ? event.durationMilliseconds : nil
        counts = selection.includeCounts && !event.counts.isEmpty
            ? Dictionary(event.counts.map { ($0.name.rawValue, $0.value) }, uniquingKeysWith: { first, _ in first })
            : nil
    }
}
