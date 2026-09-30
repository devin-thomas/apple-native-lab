import Foundation
import LabDomain

/// The one tool an extractor may use: a read-only search of the offered samples.
///
/// It takes one short word and returns at most `ProposalLimits.lookupResults` lines, each a
/// sample's title and the start of its note. It searches through the backend as the proposer, so
/// the service authorizes every call as a model-tool read, and it only ever shows samples that were
/// offered as candidates. It cannot change anything: the closure it holds can only search.
public struct SampleLookup: Sendable {
    private let search: @Sendable (ItemFilter) async -> [LabItem]
    private let offered: Set<ItemID>

    /// - Parameters:
    ///   - candidates: The samples the extractor was offered. Results outside them are dropped.
    ///   - search: A read through the service as the proposer.
    public init(candidates: [SampleCandidate], search: @escaping @Sendable (ItemFilter) async -> [LabItem]) {
        self.search = search
        offered = Set(candidates.map(\.id))
    }

    /// A lookup that finds nothing, for extractors that do not search.
    public static let none = SampleLookup(candidates: [], search: { _ in [] })

    /// The samples matching one word, as bounded text for a model. Invalid input gets a short
    /// sentence instead of an error, so a malformed tool call cannot stop the session.
    public func describe(_ word: String) async -> String {
        let matches = await find(word)
        guard let matches else { return "Search for one short word, such as a color or a material." }
        guard !matches.isEmpty else { return "No sample matches that word." }
        return matches.map { candidate in
            "\(candidate.title): \(Self.truncated(candidate.note, to: ProposalLimits.lookupNoteLength))"
        }.joined(separator: "\n")
    }

    /// The offered samples matching one word, or `nil` when the word is not one short word.
    public func find(_ word: String) async -> [SampleCandidate]? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= ProposalLimits.lookupWord,
              !trimmed.contains(where: \.isNewline),
              let filter = try? ItemFilter(text: trimmed, limit: ItemFilter.allowedLimits.upperBound)
        else { return nil }
        let items = await search(filter)
        return Array(items.filter { offered.contains($0.id) }.prefix(ProposalLimits.lookupResults).map(SampleCandidate.init))
    }

    static func truncated(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}
