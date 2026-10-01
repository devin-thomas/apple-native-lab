import CryptoKit
import Foundation

/// Exact fields that would leave the device for a Private Cloud Compute request.
///
/// Shown before any cloud call. Field names and lengths are recorded; raw prompt text is held
/// only for the on-screen preview and never copied into a usage receipt or diagnostic event.
public struct OutgoingFieldPreview: Hashable, Sendable {
    /// One named field that would be sent.
    public struct Field: Hashable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let characterCount: Int
        /// The exact value shown to the person before they consent. Never written to diagnostics.
        public let value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
            characterCount = value.count
        }
    }

    public let fields: [Field]
    /// SHA-256 of the canonical field list, used to bind a `ConsentGrant`.
    public let digest: String

    public init(fields: [Field]) {
        self.fields = fields
        digest = Self.digest(of: fields)
    }

    /// A preview for the observatory's bundled fixture prompt.
    public static func fixture(prompt: String, locale: String = "en_US") -> OutgoingFieldPreview {
        OutgoingFieldPreview(fields: [
            Field(name: "prompt", value: prompt),
            Field(name: "locale", value: locale),
            Field(name: "model", value: "PrivateCloudComputeLanguageModel"),
            Field(name: "sampling", value: "greedy"),
        ])
    }

    /// Names and lengths only: safe for usage receipts and diagnostics.
    public var telemetrySafeSummary: [(name: String, characterCount: Int)] {
        fields.map { ($0.name, $0.characterCount) }
    }

    private static func digest(of fields: [Field]) -> String {
        // Length prefixes keep embedded delimiters from aliasing a different field list.
        let canonical = fields
            .map { "\($0.name.utf8.count):\($0.name)\($0.value.utf8.count):\($0.value)" }
            .joined()
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
