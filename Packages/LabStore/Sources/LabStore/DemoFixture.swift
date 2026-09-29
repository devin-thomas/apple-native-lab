import CryptoKit
import Foundation
import LabDomain

/// A demo seed file, read and validated before anything reaches the store.
///
/// The seed is data (`Fixtures/demo/seed.json` in the repository), not code. Loading it checks the
/// whole file first: its size, that it is JSON of this format and version, that it has exactly the
/// known fields, that every value is valid, and that the seed is consistent. A file that fails any
/// check produces an error and no seed, so it cannot leave partial state behind or block a later
/// valid file. Commit the seed with `DomainOperation.resetDemo(seed:)` through `OperationService`.
///
/// File format, version 1:
///
/// ```json
/// {
///   "format": "native-lab-demo-seed",
///   "formatVersion": 1,
///   "seedVersion": 1,
///   "provenance": "Where the content comes from and its license.",
///   "collections": [{ "id": "<UUID>", "title": "…" }],
///   "items": [{ "id": "<UUID>", "collection": "<collection UUID>", "title": "…", "note": "…" }]
/// }
/// ```
public struct DemoFixture: Hashable, Sendable {
    public static let format = "native-lab-demo-seed"
    public static let supportedFormatVersion = 1
    public static let maximumByteCount = 1 << 20

    public let seed: DemoSeed
    public let provenance: String
    /// The SHA-256 of the file's bytes, in lowercase hex, for evidence records.
    public let sha256: String

    public init(contentsOf url: URL) throws(DemoFixtureError) {
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: Self.maximumByteCount + 1) ?? Data()
        } catch {
            throw .unreadable
        }
        try self.init(data: data)
    }

    public init(data: Data) throws(DemoFixtureError) {
        guard data.count <= Self.maximumByteCount else { throw .tooLarge(limit: Self.maximumByteCount) }
        let file: SeedFile
        do {
            file = try JSONDecoder().decode(SeedFile.self, from: data)
        } catch let error as DemoFixtureError {
            throw error
        } catch let error as DecodingError {
            throw Self.describe(error)
        } catch {
            throw .notJSON
        }
        seed = try file.seed()
        provenance = file.provenance
        sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func describe(_ error: DecodingError) -> DemoFixtureError {
        switch error {
        case .dataCorrupted(let context) where context.codingPath.isEmpty:
            .notJSON
        case .typeMismatch(_, let context) where context.codingPath.isEmpty:
            .unsupportedFormat
        case .dataCorrupted(let context), .typeMismatch(_, let context), .valueNotFound(_, let context):
            .malformed(path: path(context.codingPath))
        case .keyNotFound(let key, let context):
            .malformed(path: path(context.codingPath + [key]))
        @unknown default:
            .notJSON
        }
    }

    /// A location such as `items[3].title`, built from keys and indexes only, never from values.
    static func path(_ codingPath: [any CodingKey]) -> String {
        codingPath.reduce(into: "") { path, key in
            if let index = key.intValue {
                path += "[\(index)]"
            } else {
                path += path.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }
}

/// Why a demo seed file was rejected. Paths name fields and positions, never content.
public enum DemoFixtureError: Error, Hashable, Sendable {
    case unreadable
    case tooLarge(limit: Int)
    /// The bytes are not a JSON document.
    case notJSON
    /// The document is not a demo seed file.
    case unsupportedFormat
    case unsupportedFormatVersion(Int)
    /// A field is missing or has the wrong type.
    case malformed(path: String)
    /// A field this format does not define. Rejected rather than silently dropped.
    case unknownField(path: String)
    case invalidValue(path: String, ValidationError)
    case invalidSeed(DemoSeedError)
}

// MARK: - File structure

private struct SeedFile: Decodable {
    let formatVersion: Int
    let seedVersion: Int
    let provenance: String
    let collections: [CollectionEntry]
    let items: [ItemEntry]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, formatVersion, seedVersion, provenance, collections, items
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .format) == DemoFixture.format else {
            throw DemoFixtureError.unsupportedFormat
        }
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        guard formatVersion == DemoFixture.supportedFormatVersion else {
            throw DemoFixtureError.unsupportedFormatVersion(formatVersion)
        }
        seedVersion = try container.decode(Int.self, forKey: .seedVersion)
        provenance = try container.decode(String.self, forKey: .provenance)
        collections = try container.decode([CollectionEntry].self, forKey: .collections)
        items = try container.decode([ItemEntry].self, forKey: .items)
    }

    func seed() throws(DemoFixtureError) -> DemoSeed {
        var collectionDrafts: [CollectionDraft] = []
        for (index, entry) in collections.enumerated() {
            let title = try validated("collections[\(index)].title") { () throws(ValidationError) in try EntityTitle(entry.title) }
            collectionDrafts.append(CollectionDraft(id: CollectionID(rawValue: entry.id), title: title))
        }
        var itemDrafts: [ItemDraft] = []
        for (index, entry) in items.enumerated() {
            let title = try validated("items[\(index)].title") { () throws(ValidationError) in try EntityTitle(entry.title) }
            let note = try validated("items[\(index)].note") { () throws(ValidationError) in try ItemNote(entry.note) }
            itemDrafts.append(ItemDraft(
                id: ItemID(rawValue: entry.id), in: CollectionID(rawValue: entry.collection), title: title, note: note
            ))
        }
        do {
            return try DemoSeed(version: seedVersion, collections: collectionDrafts, items: itemDrafts)
        } catch {
            throw .invalidSeed(error)
        }
    }

    private func validated<Value>(_ path: String, _ make: () throws(ValidationError) -> Value) throws(DemoFixtureError) -> Value {
        do { return try make() } catch { throw .invalidValue(path: path, error) }
    }
}

private struct CollectionEntry: Decodable {
    let id: UUID
    let title: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
    }
}

private struct ItemEntry: Decodable {
    let id: UUID
    let collection: UUID
    let title: String
    let note: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, collection, title, note
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        collection = try container.decode(UUID.self, forKey: .collection)
        title = try container.decode(String.self, forKey: .title)
        note = try container.decode(String.self, forKey: .note)
    }
}

private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private func rejectUnknownKeys<Keys: CodingKey & CaseIterable>(in decoder: any Decoder, allowed: Keys.Type) throws {
    let known = Set(Keys.allCases.map(\.stringValue))
    let container = try decoder.container(keyedBy: AnyKey.self)
    if let unknown = container.allKeys.map(\.stringValue).sorted().first(where: { !known.contains($0) }) {
        throw DemoFixtureError.unknownField(path: DemoFixture.path(decoder.codingPath + [AnyKey(stringValue: unknown)]))
    }
}
