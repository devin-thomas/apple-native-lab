import Foundation

/// Masks values under secret-shaped field names in the in-app model-step inspection. This is a
/// display courtesy, not the export guarantee: a field name cannot say whether a value is secret,
/// so recipe exports and Shortcuts results withhold every typed value instead (`RecipeExport`).
/// Shortcuts Storage is not a vault (S04).
public enum SecretRedaction {
    public static let placeholder = "[redacted]"

    /// Field names treated as secrets, compared without regard to case, separators, or plurals.
    private static let secretTokens: Set<String> = [
        "secret", "secrets",
        "password", "passwords", "passwd", "passphrase",
        "token", "tokens", "accesstoken", "refreshtoken",
        "apikey", "apisecret",
        "credential", "credentials",
        "privatekey", "privkey",
        "authorization", "authheader",
        "clientsecret",
        "cookie", "cookies",
        "sessionkey",
    ]

    /// Whether a field name is secret-shaped.
    public static func isSecretField(_ name: String) -> Bool {
        let compact = name.lowercased().filter { $0.isLetter || $0.isNumber }
        if secretTokens.contains(compact) { return true }
        // Compound names such as "api_key" or "userPassword".
        for token in secretTokens where compact.contains(token) {
            return true
        }
        return false
    }

    /// Copies `fields`, replacing every secret-shaped value with `placeholder`.
    public static func redact(_ fields: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in fields {
            result[key] = isSecretField(key) ? placeholder : value
        }
        return result
    }

    /// True when any field would be redacted.
    public static func containsSecrets(_ fields: [String: String]) -> Bool {
        fields.keys.contains { isSecretField($0) }
    }
}
