import Foundation
import LabDomain

/// One line of recognized text. Below `InspectLimits.certainConfidence` it stays an uncertain
/// suggestion the person can edit; it is never applied on its own.
public struct RecognizedLine: Hashable, Sendable {
    public let text: String
    public let confidence: Double

    public var isUncertain: Bool { confidence < InspectLimits.certainConfidence }

    public init(text: String, confidence: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = trimmed.count > InspectLimits.lineLength ? String(trimmed.prefix(InspectLimits.lineLength)) : trimmed
        self.text = clipped
        self.confidence = min(max(confidence, 0), 1)
    }
}

/// A barcode's payload stored as text.
///
/// `canExecute` is fixed false. This type has no opener: a payload that looks like a link, a
/// shortcut, or an instruction is still characters in the lab record, and applying the record
/// creates an item. It does not run the payload.
public struct BarcodeReading: Hashable, Sendable {
    public let payload: String
    public let symbology: String
    public let confidence: Double

    public var canExecute: Bool { false }

    public init(payload: String, symbology: String, confidence: Double) {
        let cleaned = payload.unicodeScalars.filter { !Self.isControl($0) }.map(Character.init)
        let text = String(cleaned)
        self.payload = text.count > InspectLimits.payload ? String(text.prefix(InspectLimits.payload)) : text
        let name = symbology.trimmingCharacters(in: .whitespacesAndNewlines)
        self.symbology = name.isEmpty ? "barcode" : name
        self.confidence = min(max(confidence, 0), 1)
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (value < 32 && value != 9 && value != 10 && value != 13) || value == 127
    }
}

/// Text an analyzer found. Empty when the analyzer could not run; the manual fields still can.
public struct OpticalReading: Hashable, Sendable {
    public var lines: [RecognizedLine]
    public var barcodes: [BarcodeReading]
    public var engine: OpticalEngine

    public init(lines: [RecognizedLine], barcodes: [BarcodeReading], engine: OpticalEngine) {
        self.lines = Array(lines.prefix(InspectLimits.lines)).filter { !$0.text.isEmpty }
        self.barcodes = Array(barcodes.prefix(InspectLimits.barcodes)).filter { !$0.payload.isEmpty }
        self.engine = engine
    }
}

public enum OpticalEngine: String, Hashable, Sendable {
    case vision
    case scripted
    case unavailable
}

/// Who wrote the description. The two non-model sources say so in `badge`.
public enum SuggestionSource: String, Hashable, Sendable {
    case onDeviceModel
    case opticalRecognition
    case manual
    case systemVisualSearch

    public var badge: String {
        switch self {
        case .onDeviceModel: "On-device model"
        case .opticalRecognition: "OCR (not a model)"
        case .manual: "Manual fields (not a model)"
        case .systemVisualSearch: "System visual search (not a command)"
        }
    }
}

/// The editable description, tied to one image by digest. Uncertain text stays in these fields
/// until a person applies the record; nothing here is a fact the lab stores by itself.
public struct InterpretationSuggestion: Hashable, Sendable {
    public var title: String
    public var body: String
    public let confidence: Double
    public let source: SuggestionSource
    public var editedByPerson: Bool
    /// SHA-256 of the image this description is about, or of the system labels when no image was kept.
    public let imageDigest: String
    public let isUncertain: Bool

    public init(
        title: String,
        body: String,
        confidence: Double,
        source: SuggestionSource,
        editedByPerson: Bool = false,
        imageDigest: String,
        isUncertain: Bool
    ) {
        self.title = title
        self.body = body
        self.confidence = min(max(confidence, 0), 1)
        self.source = source
        self.editedByPerson = editedByPerson
        self.imageDigest = imageDigest
        self.isUncertain = isUncertain
    }

    public func edited(title: String, body: String) -> InterpretationSuggestion {
        var copy = self
        copy.title = title
        copy.body = body
        copy.editedByPerson = true
        return copy
    }
}

/// One inspection a person can review. The only domain operation it can become is a new item.
public struct Observation: Hashable, Sendable {
    public let evidence: ImageEvidence
    public let consent: CaptureConsent
    public let lines: [RecognizedLine]
    public let barcodes: [BarcodeReading]
    public var suggestion: InterpretationSuggestion

    public init(
        evidence: ImageEvidence,
        consent: CaptureConsent,
        lines: [RecognizedLine],
        barcodes: [BarcodeReading],
        suggestion: InterpretationSuggestion
    ) {
        self.evidence = evidence
        self.consent = consent
        self.lines = lines
        self.barcodes = barcodes
        self.suggestion = suggestion
    }

    /// A title the domain will accept, or why not.
    public var titleIssue: String? {
        let trimmed = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Type a title before applying." }
        if trimmed.count > InspectLimits.title { return "The title is longer than \(InspectLimits.title) characters." }
        if trimmed.containsControlCharacter() { return "The title cannot contain a control character." }
        return nil
    }

    public var isApprovable: Bool { titleIssue == nil }

    /// The one operation this observation is allowed to become.
    ///
    /// Barcode payloads are copied into the note as text. The operation is always `createItem`.
    public func operation(itemID: ItemID = ItemID()) throws(InspectFailure) -> DomainOperation {
        if let titleIssue { throw .invalidText(titleIssue) }
        let title: EntityTitle
        let note: ItemNote
        do {
            title = try EntityTitle(suggestion.title)
            note = try ItemNote(recordNote())
        } catch {
            throw .invalidText(error.inspectSentence)
        }
        guard title.value.count <= InspectLimits.title else { throw .invalidText("The title is longer than \(InspectLimits.title) characters.") }
        return .createItem(draft: ItemDraft(id: itemID, in: PointInspect.collectionID, title: title, note: note))
    }

    /// Provenance first, then OCR, then each barcode as text, then the editable description.
    public func recordNote() -> String {
        var parts = [
            "Image \(evidence.digest) (\(evidence.byteCount) bytes, on device).",
            "Source: \(evidence.origin.label).",
            "Visual search: \(consent.visualSearch.label).",
        ]
        if lines.isEmpty {
            parts.append("OCR: none.")
        } else {
            parts.append("OCR:")
            for line in lines {
                parts.append("- \(line.text)\(line.isUncertain ? " (uncertain)" : "")")
            }
        }
        if barcodes.isEmpty {
            parts.append("Barcodes: none.")
        } else {
            parts.append("Barcodes, stored as text:")
            for code in barcodes {
                parts.append("- \(code.symbology): \(code.payload)")
            }
        }
        let body = suggestion.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            parts.append("\(suggestion.source.badge): \(body)")
        }
        var note = parts.joined(separator: "\n")
        if note.count > InspectLimits.note {
            note = String(note.prefix(InspectLimits.note))
        }
        return note
    }
}

extension ValidationError {
    var inspectSentence: String {
        switch self {
        case .emptyTitle: "Type a title before applying."
        case .titleTooLong: "The title is too long."
        case .noteTooLong: "The record is too long."
        case .controlCharacter: "The record cannot contain a control character."
        default: "The record's text is not valid."
        }
    }
}

private extension String {
    func containsControlCharacter() -> Bool {
        unicodeScalars.contains { scalar in
            (scalar.value < 32) || scalar.value == 127
        }
    }
}
