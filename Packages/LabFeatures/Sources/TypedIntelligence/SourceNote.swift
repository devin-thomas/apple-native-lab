import Foundation

/// The note an extractor reads. Its text is data: nothing in it selects an operation, a target
/// outside the offered samples, an adapter, or a permission, and it never enters a log.
public struct SourceNote: Hashable, Sendable {
    public enum Origin: Hashable, Sendable {
        /// One of the experiment's original fixtures, bundled with the host.
        case fixture(IntelligenceFixture)
        /// Text supplied some other way, such as a test.
        case supplied
    }

    public let origin: Origin
    public let text: String

    /// Refuses empty text, text beyond `ProposalLimits.sourceNote` characters, and control
    /// characters other than line breaks and tabs.
    public init(_ text: String, origin: Origin = .supplied) throws(SourceNoteError) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .empty }
        guard text.count <= ProposalLimits.sourceNote else { throw .tooLong(limit: ProposalLimits.sourceNote) }
        let allowed: Set<Unicode.Scalar> = ["\n", "\r", "\t"]
        guard !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && !allowed.contains($0) }) else {
            throw .controlCharacter
        }
        self.text = text
        self.origin = origin
    }
}

public enum SourceNoteError: Error, Hashable, Sendable {
    case empty
    case tooLong(limit: Int)
    case controlCharacter
    /// The fixture file is missing from the bundle or is not UTF-8.
    case fixtureUnreadable

    public var message: String {
        switch self {
        case .empty: "The note is empty."
        case .tooLong(let limit): "The note is longer than \(limit) characters, so no extractor reads it."
        case .controlCharacter: "The note contains control characters, so no extractor reads it."
        case .fixtureUnreadable: "The sample note is missing from this build."
        }
    }
}

/// The experiment's original notes, in `Fixtures/intelligence/`. Each is synthetic text written
/// for this project; the host bundles the files as resources.
public enum IntelligenceFixture: String, CaseIterable, Hashable, Sendable, Identifiable {
    /// A studio note that says "the blue one" and could mean more than one pigment swatch.
    case ambiguousNote = "intelligence-ambiguous-note"
    /// A note about one paper sample followed by text that imitates instructions and an approval
    /// token. The instructions are data and cannot change anything.
    case injectedNote = "intelligence-injected-note"

    public var id: String { rawValue }

    public var fileName: String { "\(rawValue).txt" }

    public var title: String {
        switch self {
        case .ambiguousNote: "Ambiguous studio note"
        case .injectedNote: "Note with injected instructions"
        }
    }

    public var summary: String {
        switch self {
        case .ambiguousNote: "Mentions “the blue one” and four samples by name."
        case .injectedNote: "One paper sample, then text that pretends to grant permissions."
        }
    }

    /// Reads the fixture from a bundle that carries it as a resource.
    public func load(from bundle: Bundle) throws(SourceNoteError) -> SourceNote {
        guard let url = bundle.url(forResource: rawValue, withExtension: "txt") else { throw .fixtureUnreadable }
        return try load(at: url)
    }

    /// Reads the fixture from a file.
    public func load(at url: URL) throws(SourceNoteError) -> SourceNote {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            throw .fixtureUnreadable
        }
        return try SourceNote(text, origin: .fixture(self))
    }
}
