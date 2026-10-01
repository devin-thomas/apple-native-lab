import Foundation
import LabDomain

/// The draft a person copies on purpose, when the continuation hint is not enough.
///
/// This is not what Handoff carries. The activity and the link have an identifier, a revision,
/// and a section index. This document has the title and the sections, so the other device can
/// import them through the operation service. A key this schema does not name is refused, including
/// a key that claims a grant or a bookmark: the document is data, and the refusal does not repeat
/// the sender's text.
public struct ContinuationDocument: Hashable, Sendable {
    public static let format = "native-lab-continuation"
    public static let schemaVersion = 1
    /// Enough for a title and an item note, and no more. A larger file is refused before it is parsed.
    public static let maximumBytes = 64 * 1024
    public static let maximumSections = 64

    public let documentID: ItemID
    public let revision: Revision
    public let title: String
    public let sections: [String]

    public init(documentID: ItemID, revision: Revision, title: String, sections: [String]) throws(PickUpError) {
        try Self.validate(title: title, sections: sections)
        self.documentID = documentID
        self.revision = revision
        self.title = title
        self.sections = sections
    }

    public init(item: LabItem) throws(PickUpError) {
        try self.init(
            documentID: item.id,
            revision: item.revision,
            title: item.title.value,
            sections: DraftText.sections(in: item.note.value)
        )
    }

    /// The note an imported item stores. Sections join on a blank line, which is how they split.
    public var note: String { DraftText.note(from: sections) }

    public var text: String { String(decoding: encoded(), as: UTF8.self) }

    // MARK: Bytes

    /// Canonical JSON: UTF-8, two-space indent, the schema's fields in a fixed order, one trailing
    /// line break. The SHA-256 of these bytes identifies one import, so a retry replays its receipt.
    public func encoded() -> Data {
        var lines = ["{"]
        lines.append("  \"format\": \(Self.jsonString(Self.format)),")
        lines.append("  \"schemaVersion\": \(Self.schemaVersion),")
        lines.append("  \"documentID\": \(Self.jsonString(documentID.rawValue.uuidString)),")
        lines.append("  \"revision\": \(revision.rawValue),")
        lines.append("  \"title\": \(Self.jsonString(title)),")
        lines.append("  \"sections\": [")
        for (index, section) in sections.enumerated() {
            let comma = index == sections.count - 1 ? "" : ","
            lines.append("    \(Self.jsonString(section))\(comma)")
        }
        lines.append("  ]")
        lines.append("}")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    public init(decoding data: Data) throws(PickUpError) {
        if data.count > Self.maximumBytes { throw .tooLarge }
        do {
            try StrictJSON.validate(Array(data), maximumDepth: 8, maximumBytes: Self.maximumBytes)
        } catch {
            throw .invalidPayload
        }
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PickUpError.invalidPayload }
            root = object
        } catch let error as PickUpError {
            throw error
        } catch {
            throw .invalidPayload
        }
        let expected: Set<String> = ["format", "schemaVersion", "documentID", "revision", "title", "sections"]
        guard Set(root.keys) == expected else { throw .invalidPayload }
        guard root["format"] as? String == Self.format else { throw .invalidPayload }
        guard Self.jsonInt(root["schemaVersion"]) == Self.schemaVersion else { throw .invalidPayload }
        guard let idText = root["documentID"] as? String, let id = UUID(uuidString: idText) else { throw .invalidPayload }
        guard let revisionNumber = Self.jsonInt(root["revision"]), let revision = Revision(rawValue: revisionNumber) else {
            throw .invalidPayload
        }
        guard let title = root["title"] as? String else { throw .invalidPayload }
        guard let rawSections = root["sections"] as? [Any] else { throw .invalidPayload }
        var sections: [String] = []
        sections.reserveCapacity(rawSections.count)
        for value in rawSections {
            guard let text = value as? String else { throw .invalidPayload }
            sections.append(text)
        }
        try self.init(documentID: ItemID(rawValue: id), revision: revision, title: title, sections: sections)
    }

    // MARK: Checks

    private static func validate(title: String, sections: [String]) throws(PickUpError) {
        guard sections.count <= maximumSections else { throw .tooLarge }
        do {
            guard try EntityTitle(title).value == title else { throw PickUpError.invalidPayload }
        } catch is PickUpError {
            throw .invalidPayload
        } catch {
            throw .invalidPayload
        }
        for section in sections {
            guard !section.contains("\n\n") else { throw .invalidPayload }
            do { _ = try ItemNote(section) } catch { throw .invalidPayload }
        }
        do {
            _ = try ItemNote(DraftText.note(from: sections))
        } catch ValidationError.noteTooLong {
            throw .tooLarge
        } catch {
            throw .invalidPayload
        }
    }

    private static func jsonInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let int = number.intValue
        guard Double(int) == number.doubleValue else { return nil }
        return int
    }

    private static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}

/// The hint and the explicit document, built only after a permitted read of the draft.
public struct ContinuationOffer: Hashable, Sendable {
    public let token: ContinuationToken
    public let userInfo: [String: String]
    public let link: URL
    public let document: ContinuationDocument

    init(token: ContinuationToken, document: ContinuationDocument) {
        self.token = token
        userInfo = ContinuationPayload.userInfo(for: token)
        link = ContinuationLink.url(for: token)
        self.document = document
    }
}
