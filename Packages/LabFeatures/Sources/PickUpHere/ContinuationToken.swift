import LabDomain

/// Where a draft lives, without any of its words.
///
/// Handoff carries this and a section index. It does not carry the title, the note, or a copy of
/// the document. The destination looks the draft up again.
public struct DocumentLocator: Hashable, Sendable {
    public let documentID: ItemID
    public let revision: Revision

    public init(documentID: ItemID, revision: Revision) {
        self.documentID = documentID
        self.revision = revision
    }
}

/// A zero-based section in a draft. Negative positions are refused rather than clamped: a clamp is
/// what the destination does when a real draft has grown shorter, not a way to accept a broken hint.
public struct SectionPosition: Hashable, Sendable {
    public let section: Int

    public init(section: Int) throws(PickUpError) {
        guard section >= 0 else { throw .invalidPayload }
        self.section = section
    }
}

/// The whole continuation hint: which draft, which revision the sender had seen, and which section.
public struct ContinuationToken: Hashable, Sendable {
    public let locator: DocumentLocator
    public let position: SectionPosition

    public init(locator: DocumentLocator, position: SectionPosition) {
        self.locator = locator
        self.position = position
    }
}

/// How a draft's note becomes sections, and how a saved index lands inside a draft that changed.
///
/// Sections are the note split on a blank line (`\n\n`). The split is the position's meaning, so
/// an imported document rejects a section that itself contains a blank line: join and split would
/// otherwise disagree. An empty note is one empty section, so there is always a place to land.
public enum DraftText {
    public static func sections(in note: String) -> [String] {
        note.components(separatedBy: "\n\n")
    }

    static func note(from sections: [String]) -> String {
        sections.joined(separator: "\n\n")
    }

    /// Moves `requested` into `0..<count` when `count` is at least 1. A count of 0 lands on 0 and
    /// reports the move whenever the request was not already 0, so the caller never indexes off
    /// the end.
    static func clamp(_ requested: Int, count: Int) -> (section: Int, clamped: Bool) {
        let last = max(count - 1, 0)
        let section = min(max(requested, 0), last)
        return (section, section != requested)
    }
}
