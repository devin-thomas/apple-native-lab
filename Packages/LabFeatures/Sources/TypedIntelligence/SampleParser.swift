import Foundation

/// The deterministic fallback: fixed rules, not a model. The interface labels its drafts as such.
///
/// Rules, in order:
/// 1. A sample is mentioned when the note contains, as a whole word and ignoring case, a word of at
///    least three letters that appears in that sample's title and in no other offered title.
/// 2. The first quoted phrase ("…" or “…”) is a proposed title. If it mentions exactly one sample,
///    that sample is the target.
/// 3. Otherwise the target is the one sample mentioned, if exactly one is. Two or more leave the
///    choice to the person, who is shown them.
/// 4. The added note is the note's first paragraph with its line breaks joined, cut at a word
///    boundary if it is longer than `ProposalLimits.addedNote`.
/// 5. Evidence is each sentence that mentions the target, word for word.
///
/// The same note and samples always give the same draft.
public struct SampleParser: NoteExtractor {
    public let source = ProposalSource.sampleParser

    public init() {}

    public func extract(_ request: ExtractionRequest) async throws(ExtractionFailure) -> ExtractionDraft {
        guard !request.candidates.isEmpty else { throw .noSamples }
        return Self.parse(request.note.text, candidates: request.candidates)
    }

    public static func parse(_ text: String, candidates: [SampleCandidate]) -> ExtractionDraft {
        let keywords = distinctiveWords(candidates)
        let mentionedSamples = mentions(in: text, candidates: candidates)

        let quote = firstQuotedPhrase(in: text)
        var target: SampleCandidate?
        if let quote {
            let quoted = Set(words(in: quote))
            let named = mentionedSamples.filter { !(keywords[$0.id] ?? []).isDisjoint(with: quoted) }
            if named.count == 1 { target = named[0] }
        }
        if target == nil, mentionedSamples.count == 1 { target = mentionedSamples[0] }

        let title = quote.map(capitalizingFirstLetter) ?? target?.title ?? ""
        let evidence: [String] = target.map { target in
            let own = keywords[target.id] ?? []
            return sentences(in: text).filter { !own.isDisjoint(with: words(in: $0)) }
        } ?? []

        return ExtractionDraft(
            sampleTitle: target?.title ?? "",
            otherPossibleSamples: mentionedSamples.filter { $0.id != target?.id }.map(\.title),
            newTitle: title,
            addedNote: firstParagraph(of: text),
            evidence: Array(evidence.prefix(ProposalLimits.evidenceCount))
        )
    }

    // MARK: Rules

    /// The samples a text names by one of their distinctive title words (rule 1), in the order
    /// each is first named. `ProposalValidator` uses the same rule to point out samples a note
    /// names that a draft did not mention.
    public static func mentions(in text: String, candidates: [SampleCandidate]) -> [SampleCandidate] {
        let keywords = distinctiveWords(candidates)
        let noteWords = words(in: text)
        var mentioned: [(position: Int, candidate: SampleCandidate)] = []
        for candidate in candidates {
            let own = keywords[candidate.id] ?? []
            if let position = noteWords.firstIndex(where: { own.contains($0) }) {
                mentioned.append((position, candidate))
            }
        }
        return mentioned.sorted { $0.position < $1.position }.map(\.candidate)
    }

    /// Each candidate's title words that no other candidate's title shares.
    static func distinctiveWords(_ candidates: [SampleCandidate]) -> [ItemIDKey: Set<String>] {
        let titleWords = candidates.map { ($0.id, Set(words(in: $0.title).filter { $0.count >= 3 })) }
        var frequency: [String: Int] = [:]
        for (_, words) in titleWords { for word in words { frequency[word, default: 0] += 1 } }
        var result: [ItemIDKey: Set<String>] = [:]
        for (id, words) in titleWords { result[id] = words.filter { frequency[$0] == 1 } }
        return result
    }

    typealias ItemIDKey = SampleCandidate.ID

    /// Lowercased runs of letters.
    static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }

    static func firstQuotedPhrase(in text: String) -> String? {
        for (open, close) in [("\"", "\""), ("“", "”")] {
            guard let start = text.range(of: open),
                  let end = text.range(of: close, range: start.upperBound..<text.endIndex) else { continue }
            let phrase = text[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !phrase.isEmpty, !phrase.contains(where: \.isNewline) { return phrase }
        }
        return nil
    }

    static func capitalizingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Sentences as they appear in the text, trimmed: each ends at `.`, `?`, or `!` followed by
    /// whitespace, or at a line break.
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if character.isNewline {
                result.append(current)
                current = ""
                continue
            }
            current.append(character)
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if ".?!".contains(character), next == nil || next!.isWhitespace {
                result.append(current)
                current = ""
            }
        }
        result.append(current)
        return result.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The first paragraph, lines joined by spaces, within `ProposalLimits.addedNote`.
    static func firstParagraph(of text: String) -> String {
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if lines.isEmpty { continue } else { break }
            }
            lines.append(trimmed)
        }
        let joined = lines.joined(separator: " ")
        guard joined.count > ProposalLimits.addedNote else { return joined }
        let cut = joined.prefix(ProposalLimits.addedNote - 1)
        let boundary = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<boundary]) + "…"
    }
}
