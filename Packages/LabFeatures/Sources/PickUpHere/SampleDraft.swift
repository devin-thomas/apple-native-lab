import Foundation
import LabDomain

/// The original draft bundled with this experiment. It is synthetic: a workbench note, not a
/// person's document. The same words are in `Fixtures/LAB-016/workbench-draft.txt`.
public enum SampleDraft {
    public static let documentID = ItemID(rawValue: UUID(uuidString: "01600000-0000-4000-8000-000000000016")!)
    /// The collection created when a lab has no collection of the person's own to import into.
    public static let collectionID = CollectionID(rawValue: UUID(uuidString: "01600000-0000-4000-8000-0000000000C0")!)
    public static let title = "Workbench layout"
    public static let sections = [
        "Bench layout",
        "The selected section is the middle of this draft. It names the shelf, not a person.",
        "Closing check",
    ]
    /// The section a continuation of the sample resumes at, when the draft has not changed.
    public static let selectedSection = 1

    public static var note: String { DraftText.note(from: sections) }

    public static func document(revision: Revision = .initial) throws(PickUpError) -> ContinuationDocument {
        try ContinuationDocument(documentID: documentID, revision: revision, title: title, sections: sections)
    }
}
