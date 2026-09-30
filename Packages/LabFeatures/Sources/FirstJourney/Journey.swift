import Foundation
import LabDomain

/// The fixed inputs of the first six-lab journey (CORE-012): the IDs, titles, and text that
/// `FirstJourneyTests` and the showcase script in `Fixtures/showcase/first-journey/` share.
///
/// Values only. No host links this target; it exists so the journey's tests have a scheme of
/// their own to belong to, and it opens no store, grants nothing, and runs nothing.
///
/// The shared object is the note `Fixtures/intelligence/intelligence-injected-note.txt`, shared or
/// pasted into the lab and added to one of the person's own collections. Its item ID is not chosen:
/// `ImportAdopter` derives it from the note's digest and the collection's ID.
public enum Journey {
    public static let fieldNotes = CollectionID(rawValue: UUID(uuidString: "06D9663A-9835-44CE-B9E9-C048717D597A")!)
    public static let fieldNotesTitle = "Field notes"
    public static let createFieldNotes = RequestID(rawValue: UUID(uuidString: "D5760E58-4EC8-4E59-A698-E5C7DEEB5D51")!)
    /// The item ID and request ID `ImportAdopter` derives for the shared note in Field notes.
    public static let object = ItemID(rawValue: UUID(uuidString: "C784FB5A-4D9A-8895-9AE7-9418D700541D")!)
    public static let addRequest = RequestID(rawValue: UUID(uuidString: "960A425D-9DD8-8548-B632-09DCEB54741D")!)

    public static let renameRequest = RequestID(rawValue: UUID(uuidString: "A25537FF-F169-4DEA-A193-3E5E5ADBCD33")!)
    public static let archiveRequest = RequestID(rawValue: UUID(uuidString: "79998709-4D82-411B-AE3E-4769B3CFA065")!)
    public static let restoreRequest = RequestID(rawValue: UUID(uuidString: "7CAA28A8-03A7-44D1-98F5-53F798C9A06D")!)
    public static let startRequest = RequestID(rawValue: UUID(uuidString: "47E2CDBA-EA7F-42BC-8A60-D126490D7A77")!)
    /// A second lab's own collection, for importing the exported object there.
    public static let imports = CollectionID(rawValue: UUID(uuidString: "102DC40B-57B2-4BB6-9D2E-64F71E2421B5")!)
    public static let importsTitle = "Imports"

    public static let renamedTitle = "Kraft card wear note"
    /// The shared note's first line, which adoption makes the object's title.
    public static let firstLine = "Kraft card: corners fray after a week in the drawer. Still takes pencil well."

    // Demo samples from Fixtures/demo/seed.json.
    public static let kraft = ItemID(rawValue: UUID(uuidString: "6E2CED9D-B946-4188-8417-2E85C6A7268C")!)
    public static let quartz = ItemID(rawValue: UUID(uuidString: "AF451890-CA80-4DE9-B18B-4007066C9177")!)
    public static let minerals = CollectionID(rawValue: UUID(uuidString: "A222A032-267A-4208-B1F9-F55D739D3C24")!)
    public static let papers = CollectionID(rawValue: UUID(uuidString: "E7EEE9BB-FA3B-41F1-805E-41BDB71B44A3")!)
    public static let kraftSeedNote = "Brown and stiff. Takes pencil well."
    /// What the sample parser, or a person in the manual editor, adds to the kraft card: the
    /// shared note's first paragraph only.
    public static let kraftNoteAfterReview = kraftSeedNote + "\n" + firstLine

    /// SHA-256 of the object's `.anlab` export at the end of the journey (revision 4). Every path
    /// that runs the journey, in any store and on any platform, must export exactly these bytes.
    public static let exportSHA256 = "fa5f337a8ca37e5529ce343022afaf92db98a5a367b9212fe7090d37efd406ea"
}
