import Foundation
import LabDomain

/// A query the index will match, or a refusal that invents nothing.
enum SearchText {
    static let maximumLength = ItemFilter.maximumTextLength

    static func validate(_ raw: String) -> SearchCheck {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .unsupported(SearchRefusal(reason: "Enter a word to search for. Nothing was invented."))
        }
        if trimmed.count > maximumLength {
            return .unsupported(SearchRefusal(reason: "Search text can have at most \(maximumLength) characters. Nothing was invented."))
        }
        if hasControlCharacter(trimmed) {
            return .unsupported(SearchRefusal(reason: "The search contains a control character, which is not allowed. Nothing was invented."))
        }
        let tokens = tokenize(fold(trimmed))
        if tokens.isEmpty {
            return .unsupported(SearchRefusal(reason: "That search has no word to match. Nothing was invented."))
        }
        return .query(ValidatedQuery(text: trimmed, tokens: tokens))
    }
}

enum SearchCheck: Sendable {
    case query(ValidatedQuery)
    case unsupported(SearchRefusal)
}

struct ValidatedQuery: Sendable {
    let text: String
    let tokens: [String]
}

func fold(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
}

func tokenize(_ folded: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    for scalar in folded.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            current.unicodeScalars.append(scalar)
        } else if !current.isEmpty {
            tokens.append(current)
            current = ""
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

private func hasControlCharacter(_ text: String) -> Bool {
    text.unicodeScalars.contains { $0.properties.generalCategory == .control }
}
