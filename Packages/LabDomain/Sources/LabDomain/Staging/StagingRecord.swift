import Foundation

/// Names one staged import. It is derived from the content's digest, so staging the same content
/// twice names the same record, and the staging area can refuse the second copy atomically.
public struct StagingID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    init(digest: ContentDigest) { rawValue = digest.derivedUUID("staging") }

    public var description: String { rawValue.uuidString }
}

/// One file held in staging: its validated name, size, and SHA-256.
public struct StagedFile: Hashable, Sendable {
    public let path: StagedPath
    public let byteCount: Int
    public let sha256: ContentDigest

    public init(path: StagedPath, byteCount: Int, sha256: ContentDigest) {
        self.path = path
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

/// What was shared. Content is private, so `description` and reflection print only its kind.
public enum StagedPayload: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case text(String)
    /// A web page: its `http` or `https` address and, when the source gave one, its title.
    case link(URL, title: String?)
    /// Files, in the order they were shared or listed in an archive. Their bytes live in the
    /// staging area next to the record.
    case files([StagedFile])

    public var kindName: String {
        switch self {
        case .text: "text"
        case .link: "link"
        case .files: "files"
        }
    }

    public var description: String { "StagedPayload.\(kindName)(<private>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [Mirror.Child](), displayStyle: .enum) }
}

/// The small, durable record of one import waiting for review.
///
/// An extension (or the host's paste and file-picker fallbacks) creates one and writes it to the
/// staging area, then finishes; it never touches the operation store. Later the app reads the
/// record back, which validates it again from its bytes, and adopts it through `ImportAdopter`
/// and `OperationService`. Staging records are kept apart from adopted records: they are files
/// in the staging area, never rows in the store, and a record that fails validation is set aside
/// without blocking the next import.
///
/// Neither the record nor its encoding holds an actor, adapter, permission, grant, or operation.
/// Decoding refuses any field the format does not define, so such a field in a forged record is
/// a rejection, not an instruction.
public struct StagingRecord: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let format = "native-lab-staging-record"
    public static let formatVersion = 1
    /// JSON nesting in a record never exceeds this.
    static let maximumRecordDepth = 4

    public let id: StagingID
    /// When the content was staged, to the second.
    public let stagedAt: Date
    public let payload: StagedPayload
    /// SHA-256 over a canonical encoding of the payload: the identity of the content.
    public let digest: ContentDigest

    /// Validates the payload against `limits` and computes its digest.
    public init(payload: StagedPayload, stagedAt: Date = Date(), limits: ImportLimits = .standard) throws(ImportRejection) {
        try Self.validate(payload, limits: limits)
        self.payload = payload
        self.stagedAt = Date(timeIntervalSince1970: stagedAt.timeIntervalSince1970.rounded(.down))
        digest = Self.digest(of: payload)
        id = StagingID(digest: digest)
    }

    /// Stages shared text that arrived as bytes, refusing ill-formed UTF-8 rather than repairing it.
    public static func text(
        utf8 bytes: some Collection<UInt8>,
        stagedAt: Date = Date(),
        limits: ImportLimits = .standard
    ) throws(ImportRejection) -> StagingRecord {
        guard bytes.count <= limits.maximumTextBytes else { throw .textTooLarge(limit: limits.maximumTextBytes) }
        switch StrictUTF8.decode(bytes) {
        case .success(let text): return try StagingRecord(payload: .text(text), stagedAt: stagedAt, limits: limits)
        case .failure(let invalid): throw .malformedUTF8(offset: invalid.offset)
        }
    }

    /// Text and link size, or the sum of the file sizes.
    public var byteCount: Int {
        switch payload {
        case .text(let text): text.utf8.count
        case .link(let url, let title): url.absoluteString.utf8.count + (title?.utf8.count ?? 0)
        case .files(let files): files.reduce(0) { $0 + $1.byteCount }
        }
    }

    public var fileCount: Int {
        if case .files(let files) = payload { files.count } else { 0 }
    }

    public var description: String { "StagingRecord(\(id), \(payload.kindName), <private>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [Mirror.Child](), displayStyle: .struct) }

    // MARK: Validation

    private static func validate(_ payload: StagedPayload, limits: ImportLimits) throws(ImportRejection) {
        switch payload {
        case .text(let text):
            guard text.utf8.count <= limits.maximumTextBytes else { throw .textTooLarge(limit: limits.maximumTextBytes) }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyContent }
            guard !text.unicodeScalars.contains(where: isDisallowedInText) else { throw .unsupportedCharacters }

        case .link(let url, let title):
            let address = url.absoluteString
            guard address.utf8.count <= limits.maximumLinkBytes else { throw .linkTooLong(limit: limits.maximumLinkBytes) }
            guard let scheme = url.scheme?.lowercased() else { throw .malformedLink }
            guard scheme == "http" || scheme == "https" else { throw .unsupportedLinkScheme }
            guard let host = url.host(), !host.isEmpty else { throw .malformedLink }
            guard url.user() == nil, url.password() == nil else { throw .linkContainsCredentials }
            guard !address.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0 == " " }) else {
                throw .malformedLink
            }
            if let title {
                guard title.utf8.count <= limits.maximumTitleBytes else { throw .titleTooLong(limit: limits.maximumTitleBytes) }
                guard !title.unicodeScalars.contains(where: isDisallowedInText) else { throw .unsupportedCharacters }
            }

        case .files(let files):
            guard !files.isEmpty else { throw .noFiles }
            guard files.count <= limits.maximumFiles else { throw .tooManyFiles(limit: limits.maximumFiles) }
            var names = StagedPathSet()
            var total = 0
            for (index, file) in files.enumerated() {
                let position = index + 1
                do {
                    _ = try StagedPath(file.path.value, limits: limits)
                } catch {
                    throw .unsafePath(file: position, error)
                }
                guard names.insert(file.path, isDirectory: false) else { throw .duplicatePath(file: position) }
                guard file.byteCount >= 0, file.byteCount <= limits.maximumTotalBytes - total else {
                    throw .totalSizeTooLarge(limit: limits.maximumTotalBytes)
                }
                total += file.byteCount
            }
        }
    }

    /// Control characters other than line breaks and tabs, which an item note cannot hold.
    private static func isDisallowedInText(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control && !["\n", "\r", "\t"].contains(scalar)
    }

    // MARK: Digest

    /// Every field is length-prefixed, so no two payloads share an encoding.
    static func digest(of payload: StagedPayload) -> ContentDigest {
        var hasher = ContentHasher()
        func field(_ bytes: some Collection<UInt8>) {
            withUnsafeBytes(of: UInt64(bytes.count).bigEndian) { hasher.update(Data($0)) }
            hasher.update(Data(bytes))
        }
        field(Array("\(format)/\(formatVersion)/\(payload.kindName)".utf8))
        switch payload {
        case .text(let text):
            field(Array(text.utf8))
        case .link(let url, let title):
            field(Array(url.absoluteString.utf8))
            field(title.map { Array("1\($0)".utf8) } ?? Array("0".utf8))
        case .files(let files):
            for file in files {
                field(Array(file.path.value.utf8))
                field(Array(String(file.byteCount).utf8))
                field(Array(file.sha256.hex.utf8))
            }
        }
        return hasher.finalize()
    }

    // MARK: Encoding

    /// The record's canonical JSON form, as the staging area stores it.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let file = RecordFile(
            format: Self.format, formatVersion: Self.formatVersion, digest: digest.hex, stagedAt: stagedAt,
            payload: PayloadFile(payload)
        )
        // Strings, integers, and a date always encode.
        return (try? encoder.encode(file)) ?? Data()
    }

    /// Reads a record back from untrusted bytes: size, strict JSON, format and version, known
    /// fields only, every value valid, and a digest that matches the content.
    public init(decoding data: Data, limits: ImportLimits = .standard) throws(ImportRejection) {
        guard data.count <= limits.maximumRecordBytes else { throw .recordTooLarge(limit: limits.maximumRecordBytes) }
        do {
            try StrictJSON.validate(data, maximumDepth: Self.maximumRecordDepth, maximumBytes: limits.maximumRecordBytes)
        } catch {
            throw .malformedRecord(error)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file: RecordFile
        do {
            file = try decoder.decode(RecordFile.self, from: data)
        } catch let rejection as ImportRejection {
            throw rejection
        } catch {
            throw .malformedRecord(nil)
        }
        let payload = try file.payload.payload(limits: limits)
        let record = try StagingRecord(payload: payload, stagedAt: file.stagedAt, limits: limits)
        guard record.digest.hex == file.digest, record.stagedAt == file.stagedAt else { throw .digestMismatch }
        self = record
    }
}

// MARK: - File structure

private struct RecordFile: Codable {
    let format: String
    let formatVersion: Int
    let digest: String
    let stagedAt: Date
    let payload: PayloadFile

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, formatVersion, digest, stagedAt, payload
    }

    init(format: String, formatVersion: Int, digest: String, stagedAt: Date, payload: PayloadFile) {
        self.format = format
        self.formatVersion = formatVersion
        self.digest = digest
        self.stagedAt = stagedAt
        self.payload = payload
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .format) == StagingRecord.format else {
            throw ImportRejection.unsupportedRecordFormat
        }
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        guard formatVersion == StagingRecord.formatVersion else { throw ImportRejection.unsupportedRecordVersion(formatVersion) }
        try requireKnownKeys(in: decoder, CodingKeys.allCases.map(\.stringValue))
        format = StagingRecord.format
        digest = try container.decode(String.self, forKey: .digest)
        stagedAt = try container.decode(Date.self, forKey: .stagedAt)
        payload = try container.decode(PayloadFile.self, forKey: .payload)
    }
}

private struct PayloadFile: Codable {
    let kind: String
    let text: String?
    let url: String?
    let title: String?
    let files: [FileEntry]?

    private enum CodingKeys: String, CodingKey {
        case kind, text, url, title, files
    }

    init(_ payload: StagedPayload) {
        kind = payload.kindName
        var text: String?
        var url: String?
        var title: String?
        var files: [FileEntry]?
        switch payload {
        case .text(let value):
            text = value
        case .link(let address, let pageTitle):
            url = address.absoluteString
            title = pageTitle
        case .files(let staged):
            files = staged.map(FileEntry.init)
        }
        self.text = text
        self.url = url
        self.title = title
        self.files = files
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        let allowed: [String] = switch kind {
        case "text": ["kind", "text"]
        case "link": ["kind", "url", "title"]
        case "files": ["kind", "files"]
        default: throw ImportRejection.unknownRecordField
        }
        try requireKnownKeys(in: decoder, allowed)
        text = try allowed.contains("text") ? container.decode(String.self, forKey: .text) : nil
        url = try allowed.contains("url") ? container.decode(String.self, forKey: .url) : nil
        title = try allowed.contains("title") ? container.decodeIfPresent(String.self, forKey: .title) : nil
        files = try allowed.contains("files") ? container.decode([FileEntry].self, forKey: .files) : nil
    }

    func payload(limits: ImportLimits) throws(ImportRejection) -> StagedPayload {
        switch (kind, text, url, files) {
        case ("text", let text?, _, _):
            return .text(text)
        case ("link", _, let address?, _):
            guard let url = URL(string: address), url.absoluteString == address else { throw .malformedLink }
            return .link(url, title: title)
        case ("files", _, _, let entries?):
            var staged: [StagedFile] = []
            for (index, entry) in entries.enumerated() {
                let path: StagedPath
                do { path = try StagedPath(entry.path, limits: limits) } catch { throw .unsafePath(file: index + 1, error) }
                guard let digest = ContentDigest(hex: entry.sha256) else { throw .malformedRecord(nil) }
                staged.append(StagedFile(path: path, byteCount: entry.byteCount, sha256: digest))
            }
            return .files(staged)
        default:
            throw .malformedRecord(nil)
        }
    }
}

private struct FileEntry: Codable {
    let path: String
    let byteCount: Int
    let sha256: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path, byteCount, sha256
    }

    init(_ file: StagedFile) {
        path = file.path.value
        byteCount = file.byteCount
        sha256 = file.sha256.hex
    }

    init(from decoder: any Decoder) throws {
        try requireKnownKeys(in: decoder, CodingKeys.allCases.map(\.stringValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        sha256 = try container.decode(String.self, forKey: .sha256)
    }
}

private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Refuses a field outside `allowed`. The error does not name the field: an attacker chooses
/// field names, and they must not reach a message or a log.
private func requireKnownKeys(in decoder: any Decoder, _ allowed: [String]) throws {
    let container = try decoder.container(keyedBy: AnyKey.self)
    if container.allKeys.contains(where: { !allowed.contains($0.stringValue) }) {
        throw ImportRejection.unknownRecordField
    }
}
