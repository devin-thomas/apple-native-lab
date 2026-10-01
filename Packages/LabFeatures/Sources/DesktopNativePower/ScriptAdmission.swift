import Foundation

/// The only commands a script or an intent may name. Anything else, including shell text, is refused.
public enum ScriptableCommand: String, Hashable, Sendable, Codable, CaseIterable {
    case importFixtureNote = "import-fixture-note"
    case showStatus = "show-status"
}

/// Turns a string from a script-shaped caller into an allowlisted command, or refuses it.
///
/// Refusal happens before any lab operation. The admitted value is an enum, so the caller that
/// runs it cannot pass the original string onward as something to execute.
public enum ScriptAdmission {
    /// Characters that mark a shell pipeline, substitution, or redirect.
    private static let shellMarks = CharacterSet(charactersIn: ";|&$`<>(){}\\!\n\r")

    public static func admit(_ raw: String) throws(DesktopPowerError) -> ScriptableCommand {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // A shell mark, a slash, or more than one word is not a command token. Refuse it before
        // any lab operation. A single unknown word is refused too, as an unknown command.
        let looksLikeShell = raw.unicodeScalars.contains { shellMarks.contains($0) }
            || token.contains("/")
            || token.contains(where: \.isWhitespace)
        if looksLikeShell { throw .shellRefused }
        guard let command = ScriptableCommand(rawValue: token) else {
            let shown = token.isEmpty ? "empty" : String(token.prefix(80))
            throw .unknownCommand(shown)
        }
        return command
    }
}
