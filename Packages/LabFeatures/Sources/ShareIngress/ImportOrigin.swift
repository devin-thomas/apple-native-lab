import Foundation
import LabDomain

/// Names one intake: everything shared, pasted, or chosen in one action.
public struct BatchID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }

    public var description: String { rawValue.uuidString }
}

/// Where and how one staged import arrived: the surface, when, which intake it was part of, its
/// position in that intake, and the type its source declared.
///
/// It is kept beside the staging record, not inside it: the staging record format (CORE-006)
/// holds only content, and refuses any field it does not define. An origin is display data. It
/// never selects the operation, the destination, the adapter, or a permission, and a missing or
/// damaged origin only makes the inbox say "origin unknown".
public struct ImportOrigin: Hashable, Sendable {
    public static let format = "native-lab-import-origin"
    public static let formatVersion = 1
    /// An origin file is never larger than this.
    public static let maximumBytes = 1_024
    /// A declared type identifier, such as `public.jpeg`, in bytes.
    public static let maximumContentTypeBytes = 128

    public let stagingID: StagingID
    public let surface: IngressSurface
    /// When the intake began, to the second.
    public let receivedAt: Date
    public let batch: BatchID
    /// 1-based position in the intake, in the order the source listed its attachments.
    public let position: Int
    /// How many attachments the intake had.
    public let count: Int
    /// The uniform type identifier the source declared, when it is a plain identifier.
    public let contentType: String?

    /// `nil` when the position is outside `1...count`, or the count is outside the import limits.
    /// A declared type that is not a plain identifier is dropped: it is provenance, not content.
    public init?(
        stagingID: StagingID,
        surface: IngressSurface,
        receivedAt: Date,
        batch: BatchID,
        position: Int,
        count: Int,
        contentType: String?
    ) {
        guard (1...ImportLimits.standard.maximumFiles).contains(count), (1...count).contains(position) else { return nil }
        self.stagingID = stagingID
        self.surface = surface
        self.receivedAt = Date(timeIntervalSince1970: receivedAt.timeIntervalSince1970.rounded(.down))
        self.batch = batch
        self.position = position
        self.count = count
        self.contentType = contentType.flatMap { Self.isPlainIdentifier($0) ? $0 : nil }
    }

    /// A reverse-DNS style identifier: ASCII letters, digits, `.`, and `-`, within the size limit.
    static func isPlainIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumContentTypeBytes
            && value.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || $0 == "." || $0 == "-") }
    }

    // MARK: Encoding

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let file = OriginFile(
            format: Self.format, formatVersion: Self.formatVersion, stagingID: stagingID.description,
            surface: surface.rawValue, receivedAt: receivedAt, batch: batch.description, position: position, count: count,
            contentType: contentType
        )
        return (try? encoder.encode(file)) ?? Data()
    }

    /// Reads an origin back from untrusted bytes: size, strict JSON, format and version, known
    /// fields only, valid values, and the staging ID the caller expects. Anything else is `nil`.
    public init?(decoding data: Data, expecting id: StagingID) {
        guard data.count <= Self.maximumBytes,
              (try? StrictJSON.validate(data, maximumDepth: 1, maximumBytes: Self.maximumBytes)) != nil
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(OriginFile.self, from: data),
              file.format == Self.format, file.formatVersion == Self.formatVersion,
              file.stagingID == id.description,
              let surface = IngressSurface(rawValue: file.surface),
              let batch = UUID(uuidString: file.batch), batch.uuidString == file.batch,
              file.contentType.map(Self.isPlainIdentifier) ?? true,
              let origin = ImportOrigin(
                  stagingID: id, surface: surface, receivedAt: file.receivedAt, batch: BatchID(rawValue: batch),
                  position: file.position, count: file.count, contentType: file.contentType
              ),
              origin.receivedAt == file.receivedAt
        else { return nil }
        self = origin
    }
}

private struct OriginFile: Codable {
    let format: String
    let formatVersion: Int
    let stagingID: String
    let surface: String
    let receivedAt: Date
    let batch: String
    let position: Int
    let count: Int
    let contentType: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, formatVersion, stagingID, surface, receivedAt, batch, position, count, contentType
    }

    init(
        format: String, formatVersion: Int, stagingID: String, surface: String, receivedAt: Date, batch: String,
        position: Int, count: Int, contentType: String?
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.stagingID = stagingID
        self.surface = surface
        self.receivedAt = receivedAt
        self.batch = batch
        self.position = position
        self.count = count
        self.contentType = contentType
    }

    init(from decoder: any Decoder) throws {
        let keys = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
        guard keys.allSatisfy({ key in CodingKeys.allCases.contains { $0.stringValue == key } }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unknown field"))
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        stagingID = try container.decode(String.self, forKey: .stagingID)
        surface = try container.decode(String.self, forKey: .surface)
        receivedAt = try container.decode(Date.self, forKey: .receivedAt)
        batch = try container.decode(String.self, forKey: .batch)
        position = try container.decode(Int.self, forKey: .position)
        count = try container.decode(Int.self, forKey: .count)
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
    }
}

private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
