import Foundation
import LabDomain

/// The manual-exchange document: one account, one scope, and the envelopes that account can show.
///
/// `kind` is `native-lab-sync-ledger`, schema 1. A private document is refused by every other
/// account. A shared document names its share and may contain envelopes from more than one member.
/// The bytes are strict JSON: duplicate keys, a public scope, and a newer schema are refused
/// before any envelope is appended.
public struct LedgerDocument: Hashable, Sendable, Codable {
    public static let kind = "native-lab-sync-ledger"
    public static let schemaVersion = 1
    public static let maximumBytes = 2_097_152
    public static let maximumEnvelopes = 4_096

    public let schemaVersion: Int
    public let kind: String
    public let account: AccountID
    public let scope: RecordScope
    public let share: ShareID?
    public let envelopes: [MutationEnvelope]

    public init(
        account: AccountID,
        scope: RecordScope,
        share: ShareID?,
        envelopes: [MutationEnvelope]
    ) throws(LedgerError) {
        try Self.validateShape(scope: scope, share: share, envelopes: envelopes, account: account)
        self.schemaVersion = Self.schemaVersion
        self.kind = Self.kind
        self.account = account
        self.scope = scope
        self.share = share
        self.envelopes = envelopes
    }

    public func encoded() throws(LedgerError) -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(self)
        } catch {
            throw .storage
        }
    }

    /// Decodes a document after `StrictJSON` accepts the bytes. Unknown fields are refused.
    public static func decode(_ data: Data) throws(LedgerError) -> LedgerDocument {
        do {
            try StrictJSON.validate(data, maximumDepth: 16, maximumBytes: maximumBytes)
        } catch {
            throw .invalidDocument(Self.describe(error))
        }
        do {
            return try JSONDecoder().decode(LedgerDocument.self, from: data)
        } catch let error as LedgerError {
            throw error
        } catch {
            throw .invalidDocument("The document could not be read as a sync ledger.")
        }
    }

    private static func validateShape(
        scope: RecordScope,
        share: ShareID?,
        envelopes: [MutationEnvelope],
        account: AccountID
    ) throws(LedgerError) {
        switch scope {
        case .private:
            guard share == nil else { throw .invalidDocument("A private document names no shared database.") }
        case .shared:
            guard let share else { throw .invalidDocument("A shared document names its shared database.") }
            guard envelopes.allSatisfy({ $0.share == share && $0.scope == .shared }) else {
                throw .invalidDocument("Every edit in a shared document belongs to that shared database.")
            }
        }
        guard envelopes.count <= maximumEnvelopes else {
            throw .invalidDocument("The document has too many edits.")
        }
        if scope == .private {
            guard envelopes.allSatisfy({ $0.account == account && $0.scope == .private && $0.share == nil }) else {
                throw .invalidDocument("A private document contains only that account's private edits.")
            }
        }
        var seen: [MutationID: MutationEnvelope] = [:]
        for envelope in envelopes {
            if let previous = seen[envelope.id] {
                guard previous == envelope else {
                    throw .invalidDocument("The document repeats an edit with different contents.")
                }
            }
            seen[envelope.id] = envelope
        }
    }

    private static func describe(_ error: StrictJSONError) -> String {
        switch error {
        case .empty: "The document is empty."
        case .tooLarge: "The document is too large."
        default: "The document is not valid JSON."
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, account, scope, share, envelopes
    }

    public init(from decoder: any Decoder) throws {
        try LedgerCoding.rejectUnknownFields(
            in: decoder,
            allowed: ["schemaVersion", "kind", "account", "scope", "share", "envelopes"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(Int.self, forKey: .schemaVersion)
        guard schema == Self.schemaVersion else {
            throw LedgerError.invalidDocument("This document uses schema \(schema), and this build reads schema \(Self.schemaVersion).")
        }
        let kind = try container.decode(String.self, forKey: .kind)
        guard kind == Self.kind else {
            throw LedgerError.invalidDocument("This document is not a sync ledger.")
        }
        let account = try container.decode(AccountID.self, forKey: .account)
        let scope = try container.decode(RecordScope.self, forKey: .scope)
        let share = try container.decodeIfPresent(ShareID.self, forKey: .share)
        let envelopes = try container.decode([MutationEnvelope].self, forKey: .envelopes)
        try self.init(account: account, scope: scope, share: share, envelopes: envelopes)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(kind, forKey: .kind)
        try container.encode(account, forKey: .account)
        try container.encode(scope, forKey: .scope)
        try container.encodeIfPresent(share, forKey: .share)
        try container.encode(envelopes, forKey: .envelopes)
    }
}
