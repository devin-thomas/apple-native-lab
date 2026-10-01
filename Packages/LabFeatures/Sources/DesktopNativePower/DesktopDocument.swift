import CryptoKit
import Foundation
import LabDomain

/// Who may see a note opened again after a relaunch.
public enum DocumentPrivacy: String, Hashable, Sendable, Codable {
    case ordinary
    /// Kept in the lab, and listed when someone opens Desktop Native Power, but not restored into a window.
    case privateContent = "private"
}

/// How a note arrived. A fixture preview is not a lab item; the other origins are.
public enum DocumentOrigin: String, Hashable, Sendable, Codable {
    case fixture
    case fileImport = "file-import"
    case selectedText = "selected-text"
    case script
}

public struct DesktopDocumentID: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(_ uuid: UUID) { self.rawValue = uuid.uuidString }

    public var description: String { rawValue }
}

public struct DesktopWindowID: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue }
}

/// A note the desktop keeps. Closing a window drops a `DesktopWindow`, not this value.
public struct DesktopDocument: Hashable, Sendable, Identifiable {
    public let id: DesktopDocumentID
    public let title: String
    public let body: String
    public let privacy: DocumentPrivacy
    public let origin: DocumentOrigin
    /// The lab item this note was committed as, or `nil` for a fixture preview.
    public let itemID: ItemID?

    public init(
        id: DesktopDocumentID,
        title: String,
        body: String,
        privacy: DocumentPrivacy,
        origin: DocumentOrigin,
        itemID: ItemID?
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.privacy = privacy
        self.origin = origin
        self.itemID = itemID
    }
}

/// One open window onto a document. Several windows may name the same document.
public struct DesktopWindow: Hashable, Sendable, Identifiable {
    public let id: DesktopWindowID
    public let documentID: DesktopDocumentID

    public init(id: DesktopWindowID, documentID: DesktopDocumentID) {
        self.id = id
        self.documentID = documentID
    }
}

/// Which windows may come back after a relaunch. Private notes are listed as withheld, never opened.
public struct SceneSnapshot: Hashable, Sendable, Codable {
    public let openDocumentIDs: [DesktopDocumentID]
    public let withheldPrivateDocumentIDs: [DesktopDocumentID]

    public init(openDocumentIDs: [DesktopDocumentID], withheldPrivateDocumentIDs: [DesktopDocumentID]) {
        self.openDocumentIDs = openDocumentIDs
        self.withheldPrivateDocumentIDs = withheldPrivateDocumentIDs
    }

    /// Scene storage for the open windows. It is document IDs only, never a note's text.
    public var storageKey: String {
        openDocumentIDs.map(\.rawValue).joined(separator: ",")
    }

    public func contains(_ secret: String) -> Bool {
        guard !secret.isEmpty else { return false }
        if storageKey.contains(secret) { return true }
        return withheldPrivateDocumentIDs.contains { $0.rawValue.contains(secret) }
    }
}

/// A validated note, ready to commit.
public struct DesktopNote: Hashable, Sendable {
    public let title: EntityTitle
    public let body: ItemNote

    public init(title: EntityTitle, body: ItemNote) {
        self.title = title
        self.body = body
    }
}

enum DesktopNoteParser {
    /// The title is the first line, shortened to a title's limit. The body is the whole text.
    static func parse(_ text: String, fallbackTitle: String) throws(DesktopPowerError) -> DesktopNote {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyText }
        let body: ItemNote
        do {
            body = try ItemNote(text)
        } catch {
            throw DesktopPowerError(error)
        }
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        let rawTitle = trimmed.isEmpty ? fallbackTitle : trimmed
        let limited = String(rawTitle.prefix(EntityTitle.maximumLength))
        do {
            return DesktopNote(title: try EntityTitle(limited), body: body)
        } catch {
            throw DesktopPowerError(error)
        }
    }

    static func parseFile(_ data: Data, filename: String) throws(DesktopPowerError) -> DesktopNote {
        guard let text = String(data: data, encoding: .utf8) else { throw .invalidText }
        let stem = (filename as NSString).deletingPathExtension
        let fallback = stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Desktop note" : stem
        return try parse(text, fallbackTitle: fallback)
    }
}

extension DesktopPowerError {
    public init(_ error: ValidationError) {
        switch error {
        case .emptyTitle:
            self = .emptyText
        case .noteTooLong(let limit), .titleTooLong(let limit):
            self = .textTooLong(limit: limit)
        default:
            self = .invalidText
        }
    }
}

/// Stable identities for the desktop collection and for one note's item and request.
enum DesktopIdentity {
    static let collectionID = CollectionID(rawValue: UUID(uuidString: "04200000-0000-4000-8000-000000000042")!)
    static let collectionRequestID = RequestID(rawValue: UUID(uuidString: "04200000-0000-4000-8000-000000000043")!)
    static let collectionTitle = "Desktop Notes"
    static let fixtureDocumentID = DesktopDocumentID(rawValue: "fixture-harbor-tally")

    static func itemID(text: String, origin: DocumentOrigin, privacy: DocumentPrivacy) -> ItemID {
        ItemID(rawValue: uuid(named: "item|\(origin.rawValue)|\(privacy.rawValue)|\(text)"))
    }

    /// Includes the adapter, so each entry point retries its own request. The item ID does not,
    /// so a second entry point finds the note instead of creating another.
    static func requestID(
        text: String,
        origin: DocumentOrigin,
        privacy: DocumentPrivacy,
        adapter: AdapterKind
    ) -> RequestID {
        RequestID(rawValue: uuid(named: "request|\(adapter.rawValue)|\(origin.rawValue)|\(privacy.rawValue)|\(text)"))
    }

    static func documentID(for itemID: ItemID) -> DesktopDocumentID {
        DesktopDocumentID(itemID.rawValue)
    }

    static func extras(origin: DocumentOrigin, privacy: DocumentPrivacy) throws(DesktopPowerError) -> ItemExtras {
        let json = "{\"desktop\":{\"origin\":\"\(origin.rawValue)\",\"privacy\":\"\(privacy.rawValue)\"}}"
        do {
            return try ItemExtras(json: json)
        } catch {
            throw .invalidText
        }
    }

    static func mark(in extras: ItemExtras) -> (origin: DocumentOrigin, privacy: DocumentPrivacy)? {
        guard let data = extras.json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let desktop = object["desktop"] as? [String: Any],
              let origin = DocumentOrigin(rawValue: desktop["origin"] as? String ?? ""),
              let privacy = DocumentPrivacy(rawValue: desktop["privacy"] as? String ?? "")
        else { return nil }
        return (origin, privacy)
    }

    private static func uuid(named name: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum DesktopFixture {
    static let resourceName = "sample-desk-note"

    static func data() throws(DesktopPowerError) -> Data {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "txt"),
              let data = try? Data(contentsOf: url)
        else { throw .unavailable }
        return data
    }

    static func text() throws(DesktopPowerError) -> String {
        let data = try data()
        guard let text = String(data: data, encoding: .utf8) else { throw .invalidText }
        return text
    }
}
