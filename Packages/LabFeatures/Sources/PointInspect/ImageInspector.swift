import Foundation

/// Reads text and barcodes from image bytes. A failure here does not discard the image: the
/// person can still type the record.
public protocol ImageInspecting: Sendable {
    func inspect(_ image: SelectedImage) async throws(InspectFailure) -> OpticalReading
}

/// No analyzer on this platform, or a stand-in for a device where Vision cannot run.
public struct UnavailableImageInspector: ImageInspecting {
    public init() {}

    public func inspect(_ image: SelectedImage) async throws(InspectFailure) -> OpticalReading {
        if Task.isCancelled { throw .cancelled }
        return OpticalReading(lines: [], barcodes: [], engine: .unavailable)
    }
}

/// A fixed reading for tests and for a labeled fixture replay.
public struct ScriptedImageInspector: ImageInspecting {
    public let reading: OpticalReading
    private let body: (@Sendable (SelectedImage) async throws(InspectFailure) -> OpticalReading)?

    public init(reading: OpticalReading) {
        self.reading = reading
        body = nil
    }

    public init(_ body: @escaping @Sendable (SelectedImage) async throws(InspectFailure) -> OpticalReading) {
        reading = OpticalReading(lines: [], barcodes: [], engine: .scripted)
        self.body = body
    }

    public func inspect(_ image: SelectedImage) async throws(InspectFailure) -> OpticalReading {
        if let body { return try await body(image) }
        return reading
    }
}

/// What a description step returns before it is tied to the image digest.
public struct InterpretationDraft: Hashable, Sendable {
    public var title: String
    public var body: String
    public var confidence: Double
    public var uncertain: Bool
    public var source: SuggestionSource

    public init(title: String, body: String, confidence: Double, uncertain: Bool, source: SuggestionSource) {
        self.title = title
        self.body = body
        self.confidence = confidence
        self.uncertain = uncertain
        self.source = source
    }
}

public protocol ImageInterpreting: Sendable {
    func interpret(_ image: SelectedImage, reading: OpticalReading) async throws(InspectFailure) -> InterpretationDraft
}

/// Builds the editable suggestion from OCR alone, labeled as not a model.
public enum OpticalRecognition {
    public static func draft(from reading: OpticalReading) -> InterpretationDraft {
        let usable = reading.lines.filter { !$0.text.isEmpty }
        let title = usable.first?.text ?? "Inspection"
        let body = usable.map(\.text).joined(separator: "\n")
        let uncertain = usable.isEmpty || usable.contains(where: \.isUncertain) || !reading.barcodes.isEmpty
        let confidence = usable.map(\.confidence).min() ?? 0
        return InterpretationDraft(
            title: title,
            body: body,
            confidence: confidence,
            uncertain: uncertain,
            source: .opticalRecognition
        )
    }
}

/// The fields a person typed. Labeled as not a model.
public struct ManualInterpretation: ImageInterpreting {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    public func interpret(_ image: SelectedImage, reading: OpticalReading) async throws(InspectFailure) -> InterpretationDraft {
        return InterpretationDraft(title: title, body: body, confidence: 1, uncertain: false, source: .manual)
    }
}

/// A fixed model answer for tests. It cannot commit.
public struct ScriptedInterpreter: ImageInterpreting {
    public let draft: InterpretationDraft
    private let body: (@Sendable (SelectedImage, OpticalReading) async throws(InspectFailure) -> InterpretationDraft)?

    public init(draft: InterpretationDraft) {
        self.draft = draft
        body = nil
    }

    public init(_ body: @escaping @Sendable (SelectedImage, OpticalReading) async throws(InspectFailure) -> InterpretationDraft) {
        draft = InterpretationDraft(title: "", body: "", confidence: 0, uncertain: true, source: .onDeviceModel)
        self.body = body
    }

    public func interpret(_ image: SelectedImage, reading: OpticalReading) async throws(InspectFailure) -> InterpretationDraft {
        if let body { return try await body(image, reading) }
        return draft
    }
}
