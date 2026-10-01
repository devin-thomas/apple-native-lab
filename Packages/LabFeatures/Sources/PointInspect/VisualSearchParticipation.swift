import CryptoKit
import Foundation

/// System visual-search labels turned into the same editable record as a chosen image.
///
/// The system's pixel buffer is not read and not stored. Labels are text. A label that looks
/// like a link or a command is still text in the suggestion, and nothing is saved until the
/// person applies the record through `PointInspectFlow`.
public enum VisualSearchParticipation {
    public static func observation(labels: [String]) -> Observation {
        let kept = labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(InspectLimits.lines)
        let joined = kept.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
        let evidence = ImageEvidence(
            digest: digest,
            byteCount: 0,
            media: nil,
            origin: .systemVisualSearch
        )
        let title = kept.first.map { String($0.prefix(InspectLimits.title)) } ?? ""
        let suggestion = InterpretationSuggestion(
            title: title,
            body: joined,
            confidence: 0.4,
            source: .systemVisualSearch,
            imageDigest: digest,
            isUncertain: true
        )
        return Observation(
            evidence: evidence,
            consent: CaptureConsent(cameraUsed: false, visualSearch: .systemQuery),
            lines: kept.map { RecognizedLine(text: $0, confidence: 0.4) },
            barcodes: [],
            suggestion: suggestion
        )
    }
}

/// The latest system-search suggestion, for the app to show when visual search opens it.
/// Labels only. Replaced wholesale; it holds no image bytes.
public actor VisualSearchHandoff {
    public static let shared = VisualSearchHandoff()

    public private(set) var observation: Observation?

    public func store(_ observation: Observation) {
        self.observation = observation
    }

    public func take() -> Observation? {
        let current = observation
        observation = nil
        return current
    }
}
