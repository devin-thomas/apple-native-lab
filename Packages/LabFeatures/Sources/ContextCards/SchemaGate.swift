import Foundation

/// What a visible sample is, for the schema gate. A lab sample has no Apple schema subject.
public enum SampleKind: Sendable {
    case labSample

    /// The installed schema domain this kind genuinely is, or `nil` when it is none of them.
    var domain: String? { nil }
    /// The installed schema entity this kind genuinely is, or `nil` when it is none of them.
    var entity: String? { nil }
}

/// A caller asking to treat a sample as one Apple schema entity.
public struct SchemaClaim: Hashable, Sendable {
    public let domain: String
    public let entity: String

    public init(domain: String, entity: String) {
        self.domain = domain
        self.entity = entity
    }
}

/// Whether a claim may be adopted. A mismatch fails the integration gate and associates nothing.
public enum SchemaDecision: Equatable, Sendable {
    case matched
    case mismatch(String)
}

/// The Apple schema domains in the iOS 27.0 SDK's `AppSchema` (read 2026-09-30), and the rule
/// that a lab sample matches none of them.
///
/// The list is the set of domains the gate recognizes. It does not adopt any of them, and it
/// does not invent a schema for a lab sample. `NotesEntity` is iOS 27.0; the others here start
/// at iOS 18.0. Watch and tvOS mark these schemas unavailable. A claim is refused on every OS.
public enum SchemaGate {
    /// Domain identifiers from `AppSchema.Entity("<domain>")` in the installed interface.
    public static let installedDomains: Set<String> = [
        "audio", "books", "browser", "calendar", "clock", "files", "journal", "mail", "maps",
        "messages", "notes", "phone", "photos", "presentation", "reader", "reminders",
        "spreadsheet", "whiteboard", "wordProcessor",
    ]

    /// `matched` only when `kind` is that exact installed entity. A lab sample never is.
    public static func decide(_ kind: SampleKind, claim: SchemaClaim) -> SchemaDecision {
        let domain = claim.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let entity = claim.entity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty, !entity.isEmpty else {
            return .mismatch("A schema needs a domain and an entity. Nothing was associated.")
        }
        let name = "\(domain).\(entity)"
        guard installedDomains.contains(domain) else {
            return .mismatch("“\(name)” is not an Apple schema in this SDK, so the integration gate failed. Nothing was associated.")
        }
        guard kind.domain == domain, kind.entity == entity else {
            return .mismatch("“\(name)” does not match this lab sample, so the integration gate failed. Nothing was associated.")
        }
        return .matched
    }
}
