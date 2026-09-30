import Foundation
import LabDomain
import LabStaging

/// One file of a staged import, as the inbox shows it.
public struct InboxFile: Hashable, Sendable {
    /// The shared name. It was validated when staged; it is a label, never a path.
    public let name: String
    public let byteCount: Int

    public init(name: String, byteCount: Int) {
        self.name = name
        self.byteCount = byteCount
    }
}

/// What a waiting import holds, read back from its validated staging record.
public enum InboxContent: Hashable, Sendable {
    case text(String)
    case link(URL, title: String?)
    case files([InboxFile])

    public var kindName: String {
        switch self {
        case .text: "text"
        case .link: "link"
        case .files: "files"
        }
    }
}

/// Whether a waiting import can be added to a collection in this build.
public enum Adoptability: Hashable, Sendable {
    case ready
    /// It stays waiting, or can be removed, but cannot be added. The reason is a sentence.
    case unavailable(ImportRejection)
}

/// One import waiting for review, validated again from its bytes when the inbox was read.
///
/// Its content is private: `description` and reflection name only its kind.
public struct InboxEntry: Identifiable, Hashable, Sendable, CustomStringConvertible, CustomReflectable {
    public struct ID: Hashable, Sendable, CustomStringConvertible {
        public let source: InboxSource
        public let staging: StagingID

        public init(source: InboxSource, staging: StagingID) {
            self.source = source
            self.staging = staging
        }

        public var description: String { "\(source.rawValue)/\(staging)" }
    }

    public let id: ID
    /// Where it came from, or `nil` when no valid origin was recorded.
    public let origin: ImportOrigin?
    public let stagedAt: Date
    public let content: InboxContent
    public let byteCount: Int
    public let adoptability: Adoptability

    public var source: InboxSource { id.source }

    /// A one-line label: the text's first line, the page title or host, or the file names.
    public var headline: String {
        switch content {
        case .text(let text):
            return Self.firstLine(of: text, limit: 80)
        case .link(let url, let title):
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? (url.host() ?? url.absoluteString) : Self.firstLine(of: trimmed, limit: 80)
        case .files(let files):
            let names = files.map(\.name)
            return names.count == 1 ? names[0] : "\(names[0]) and \(names.count - 1) more"
        }
    }

    public var description: String { "InboxEntry(\(id), \(content.kindName), <private>)" }
    public var customMirror: Mirror { Mirror(self, children: [Mirror.Child](), displayStyle: .struct) }

    static func firstLine(of text: String, limit: Int) -> String {
        let line = text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let spaced = String(String.UnicodeScalarView(line.unicodeScalars.map { $0.properties.generalCategory == .control ? " " : $0 }))
        return spaced.count > limit ? String(spaced.prefix(limit - 1)) + "…" : spaced
    }
}

/// An import set aside because it no longer validated. Only its rejection code is kept.
public struct QuarantineEntry: Identifiable, Hashable, Sendable {
    public struct ID: Hashable, Sendable {
        public let source: InboxSource
        public let quarantine: QuarantineID
    }

    public let id: ID
    /// Where it came from, when its origin is still recorded.
    public let origin: ImportOrigin?
    public let code: String?

    public var source: InboxSource { id.source }

    /// Why it was set aside, as a sentence. The code alone names no content.
    public var message: String {
        "This import was changed or damaged after it was shared, so it was set aside. Share it again."
    }
}

/// The inbox at one moment: every waiting import, in arrival order, and every set-aside import.
public struct InboxSnapshot: Hashable, Sendable {
    public let entries: [InboxEntry]
    public let quarantined: [QuarantineEntry]
    /// The folders read, with any that could not be opened left out.
    public let sources: [InboxSource]

    public static let empty = InboxSnapshot(entries: [], quarantined: [], sources: [])

    public func entry(_ id: InboxEntry.ID) -> InboxEntry? { entries.first { $0.id == id } }
}
