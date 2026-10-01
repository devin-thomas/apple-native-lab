import Foundation

/// The first-run shelf: six original labels, two of which share a word, one of which is private,
/// and one of which the person has not opted in. Nothing here is a personal account or a real note.
public enum MessyCollection {
    public static let cedarTray = document(
        "A4C1E0B2-7D33-4F18-9A60-6B1F0C2D1001",
        title: "Cedar tray label",
        body: "Cedar slats in tray 4 on the north shelf. This is the tray, not the oil.",
        optedIn: true
    )
    public static let cedarOil = document(
        "A4C1E0B2-7D33-4F18-9A60-6B1F0C2D1002",
        title: "Cedar oil vial",
        body: "A small vial of cedar oil on shelf 2. It is not the tray of slats.",
        optedIn: true
    )
    public static let cobaltCard = document(
        "A4C1E0B2-7D33-4F18-9A60-6B1F0C2D1003",
        title: "Cobalt swatch card",
        body: "A blue pigment swatch in drawer B. No wood is named here.",
        optedIn: true
    )
    public static let lockerNote = document(
        "A4C1E0B2-7D33-4F18-9A60-6B1F0C2D1004",
        title: "Private locker note",
        body: "Practice card for locker 9. The word on the card is birchbark.",
        optedIn: true,
        isPrivate: true
    )
    /// Present on the shelf and deliberately not in the index. Its word must never be a hit.
    public static let packingSlip = document(
        "A4C1E0B2-7D33-4F18-9A60-6B1F0C2D1005",
        title: "Unlisted packing slip",
        body: "Linen bolts. The slip's own word is flaxshuttle.",
        optedIn: false
    )
    public static let emptyBin = document(
        "A4C1E0B2-7D33-4F18-9A60-6B1F0C2D1006",
        title: "Empty bin tag",
        body: "Bin 12 is empty.",
        optedIn: true
    )

    public static let corpus: [SearchDocument] = [cedarTray, cedarOil, cobaltCard, lockerNote, packingSlip, emptyBin]

    public static var ids: Set<SearchRecordID> { Set(corpus.map(\.id)) }

    private static func document(
        _ uuid: String,
        title: String,
        body: String,
        optedIn: Bool,
        isPrivate: Bool = false
    ) -> SearchDocument {
        SearchDocument(
            id: SearchRecordID(rawValue: UUID(uuidString: uuid)!),
            title: title,
            body: body,
            optedIn: optedIn,
            isPrivate: isPrivate
        )
    }
}
