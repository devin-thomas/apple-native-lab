import Foundation
import LabDomain

/// LAB-012 Point, Inspect, Propose: a chosen image becomes a reviewable lab record.
///
/// OCR and barcodes are deterministic. A model may suggest a description, and the person edits
/// it before anything is stored. AI proposes; deterministic code commits (ADR-007). Reads and
/// proposals use the model-tool adapter, whose ceiling is read and propose (ADR-011). The only
/// way into the store is `PointInspectBackend.commit`, which takes an `ApprovedInspection`.
public enum PointInspect {
    public static let experimentID = "LAB-012"

    /// The scope every inspection proposes with. Its adapter can never commit.
    public static let proposer = ActorScope(adapter: .modelTool, grants: [.read, .propose])

    /// The user collection inspection records are created in. It is created only when a person
    /// applies a record, never when they open the experiment.
    public static let collectionID = CollectionID(rawValue: UUID(uuidString: "01201200-0000-4000-8000-000000000012")!)

    public static let collectionTitle = "Inspections"

    /// How long a read may take before it is abandoned.
    public static let defaultTimeLimit: Duration = .seconds(30)
}

/// Bounds for one inspection. They are tighter than the domain's where a record is concerned.
public enum InspectLimits {
    /// A chosen image, in bytes.
    public static let imageBytes = 8 * 1024 * 1024
    /// A suggested title, in characters. The domain allows `EntityTitle.maximumLength`.
    public static let title = 80
    /// The editable description, in characters.
    public static let body = 600
    /// The stored note, in characters, including provenance.
    public static let note = 1_800
    /// OCR lines kept from one image.
    public static let lines = 40
    /// Characters of one OCR line.
    public static let lineLength = 200
    /// Barcodes kept from one image.
    public static let barcodes = 16
    /// Characters of one barcode payload stored as text.
    public static let payload = 500
    /// A recognition at or above this confidence is not marked uncertain.
    public static let certainConfidence = 0.75
}
