import Foundation
import LabDomain
import LabStore

extension DemoScript {
    public static let format = "native-lab-demo-script"
    public static let supportedFormatVersion = 1
    public static let fileName = "script.json"
    public static let maximumFileBytes = 256 * 1024
    static let maximumDepth = 16

    /// Loads `script.json` and the seed it names from one folder.
    ///
    /// Both files are read through the confined reader: ordinary, visible, singly linked files
    /// below `folder`, with no symbolic link on the way. Each must be strict JSON (no duplicate
    /// keys) before a decoder sees it, and every field must be one the format defines. The input
    /// hashes are the SHA-256 of the exact bytes read.
    ///
    /// Format, version 1 (see `Fixtures/showcase/README.md`):
    ///
    /// ```json
    /// {
    ///   "format": "native-lab-demo-script", "formatVersion": 1,
    ///   "id": "atlas-basics", "subject": "CORE-009", "title": "…",
    ///   "dataTier": "public-fixture", "provenance": "…", "seed": "seed.json",
    ///   "untested": ["…"],
    ///   "steps": [
    ///     { "id": "approve-reset", "approve": "reset" },
    ///     { "id": "reset", "request": "<UUID>", "resetDemo": {} },
    ///     { "id": "find-glass", "find": { "text": "glass", "expect": ["<item UUID>"] } },
    ///     { "id": "rename", "request": "<UUID>", "updateItem": { "id": "<UUID>", "expected": 1, "title": "…" } },
    ///     { "id": "undo-rename", "request": "<UUID>", "undo": "rename" },
    ///     { "id": "start", "request": "<UUID>", "setSession": { "id": "<UUID>", "running": true } }
    ///   ]
    /// }
    /// ```
    public init(folder: URL) throws(DemoScriptError) {
        let scriptBytes: Data
        do {
            scriptBytes = try ConfinedFile.read(
                ConfinedFile.validatedPath(Self.fileName), under: folder, maximumBytes: Self.maximumFileBytes
            )
        } catch {
            throw .scriptFile(error)
        }
        do {
            try StrictJSON.validate(scriptBytes, maximumDepth: Self.maximumDepth, maximumBytes: Self.maximumFileBytes)
        } catch {
            throw .invalidJSON(error)
        }
        let file: ScriptFile
        do {
            file = try JSONDecoder().decode(ScriptFile.self, from: scriptBytes)
        } catch let failure as ScriptFileFailure {
            throw failure.error
        } catch let error as DecodingError {
            throw Self.describe(error)
        } catch {
            throw .malformed(path: "")
        }

        let seedPath: StagedPath
        do { seedPath = try ConfinedFile.validatedPath(file.seed) } catch { throw .seedFile(error) }
        let seedBytes: Data
        do {
            seedBytes = try ConfinedFile.read(seedPath, under: folder, maximumBytes: DemoFixture.maximumByteCount)
        } catch {
            throw .seedFile(error)
        }
        do {
            try StrictJSON.validate(seedBytes, maximumDepth: Self.maximumDepth, maximumBytes: DemoFixture.maximumByteCount)
        } catch {
            throw .invalidSeedJSON(error)
        }
        let fixture: DemoFixture
        do { fixture = try DemoFixture(data: seedBytes) } catch { throw .seed(error) }

        try self.init(
            id: file.id,
            subject: file.subject,
            title: file.title,
            dataTier: file.dataTier,
            provenance: file.provenance,
            seed: fixture.seed,
            steps: file.steps,
            untested: file.untested,
            inputs: [
                DemoInput(name: "script:\(file.id)", sha256: ContentDigest.sha256(scriptBytes)),
                DemoInput(name: "seed:\(file.id)", sha256: ContentDigest.sha256(seedBytes)),
            ]
        )
    }

    private static func describe(_ error: DecodingError) -> DemoScriptError {
        switch error {
        case .typeMismatch(_, let context) where context.codingPath.isEmpty:
            .unsupportedFormat
        case .dataCorrupted(let context), .typeMismatch(_, let context), .valueNotFound(_, let context):
            .malformed(path: ScriptFile.path(context.codingPath))
        case .keyNotFound(let key, let context):
            .malformed(path: ScriptFile.path(context.codingPath + [key]))
        @unknown default:
            .malformed(path: "")
        }
    }
}

// MARK: - File structure

/// A refusal raised inside decoding, carried out unchanged.
private struct ScriptFileFailure: Error {
    let error: DemoScriptError
}

private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private func rejectUnknownKeys(in decoder: any Decoder, allowed: Set<String>) throws {
    let container = try decoder.container(keyedBy: AnyKey.self)
    if let unknown = container.allKeys.map(\.stringValue).sorted().first(where: { !allowed.contains($0) }) {
        throw ScriptFileFailure(error: .unknownField(path: ScriptFile.path(decoder.codingPath + [AnyKey(stringValue: unknown)])))
    }
}

private func invalid(_ decoder: any Decoder, _ key: String) -> ScriptFileFailure {
    ScriptFileFailure(error: .invalidValue(path: ScriptFile.path(decoder.codingPath + [AnyKey(stringValue: key)])))
}

private struct ScriptFile: Decodable {
    let id: DemoName
    let subject: String
    let title: String
    let dataTier: DataTier
    let provenance: String
    let seed: String
    let untested: [String]
    let steps: [DemoStep]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, formatVersion, id, subject, title, dataTier, provenance, seed, untested, steps
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .format) == DemoScript.format else {
            throw ScriptFileFailure(error: .unsupportedFormat)
        }
        let version = try container.decode(Int.self, forKey: .formatVersion)
        guard version == DemoScript.supportedFormatVersion else {
            throw ScriptFileFailure(error: .unsupportedFormatVersion(version))
        }
        try rejectUnknownKeys(in: decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        id = try container.decode(DemoName.self, forKey: .id)
        subject = try container.decode(String.self, forKey: .subject)
        title = try container.decode(String.self, forKey: .title)
        guard let tier = DataTier(rawValue: try container.decode(String.self, forKey: .dataTier)) else {
            throw invalid(decoder, CodingKeys.dataTier.rawValue)
        }
        dataTier = tier
        provenance = try container.decode(String.self, forKey: .provenance)
        seed = try container.decode(String.self, forKey: .seed)
        untested = try container.decodeIfPresent([String].self, forKey: .untested) ?? []
        steps = try container.decode([StepEntry].self, forKey: .steps).map(\.step)
    }

    /// A location such as `steps[3].find.expect`, built from keys and indexes only.
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

private struct StepEntry: Decodable {
    let step: DemoStep

    private static let performKeys: [String] = [
        "resetDemo", "createCollection", "updateCollection", "archiveCollection", "restoreCollection",
        "createItem", "updateItem", "archiveItem", "restoreItem", "setSession", "undo",
    ]
    private static let actionKeys = ["approve", "find"] + performKeys

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: Set(["id", "description", "request"] + Self.actionKeys))
        let container = try decoder.container(keyedBy: AnyKey.self)
        let id = try container.decode(DemoName.self, forKey: AnyKey(stringValue: "id"))
        let description = try container.decodeIfPresent(String.self, forKey: AnyKey(stringValue: "description"))
        let present = Self.actionKeys.filter { container.contains(AnyKey(stringValue: $0)) }
        guard present.count == 1, let actionKey = present.first else {
            throw ScriptFileFailure(error: .malformed(path: ScriptFile.path(decoder.codingPath) + ".<one action>"))
        }
        let key = AnyKey(stringValue: actionKey)
        let requestKey = AnyKey(stringValue: "request")
        let action: DemoAction
        switch actionKey {
        case "approve":
            guard !container.contains(requestKey) else { throw ScriptFileFailure(error: .unknownField(path: ScriptFile.path(decoder.codingPath + [requestKey]))) }
            action = .approve(try container.decode(DemoName.self, forKey: key))
        case "find":
            guard !container.contains(requestKey) else { throw ScriptFileFailure(error: .unknownField(path: ScriptFile.path(decoder.codingPath + [requestKey]))) }
            action = .find(try container.decode(FindEntry.self, forKey: key).find)
        default:
            let request = RequestID(rawValue: try container.decode(UUID.self, forKey: requestKey))
            let operation: ScriptedOperation
            switch actionKey {
            case "resetDemo":
                _ = try container.decode(EmptyEntry.self, forKey: key)
                operation = .resetDemo
            case "undo":
                operation = .undo(of: try container.decode(DemoName.self, forKey: key))
            default:
                operation = .domain(try container.decode(OperationEntry.self, forKey: key).operation(actionKey))
            }
            action = .perform(request: request, operation: operation)
        }
        step = DemoStep(id, action, description: description)
    }
}

private struct EmptyEntry: Decodable {
    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: [])
    }
}

/// The payload of one domain operation. Which fields are allowed and required depends on the
/// operation, so the fields are read here and checked once the operation is known.
private struct OperationEntry: Decodable {
    let path: String
    let keys: Set<String>
    let id: UUID?
    let collection: UUID?
    let expected: Int?
    let title: String?
    let note: String?
    let running: Bool?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        path = ScriptFile.path(decoder.codingPath)
        keys = Set(container.allKeys.map(\.stringValue))
        id = try container.decodeIfPresent(UUID.self, forKey: AnyKey(stringValue: "id"))
        collection = try container.decodeIfPresent(UUID.self, forKey: AnyKey(stringValue: "collection"))
        expected = try container.decodeIfPresent(Int.self, forKey: AnyKey(stringValue: "expected"))
        title = try container.decodeIfPresent(String.self, forKey: AnyKey(stringValue: "title"))
        note = try container.decodeIfPresent(String.self, forKey: AnyKey(stringValue: "note"))
        running = try container.decodeIfPresent(Bool.self, forKey: AnyKey(stringValue: "running"))
    }

    private func failure(_ make: (String) -> DemoScriptError, _ key: String) -> ScriptFileFailure {
        ScriptFileFailure(error: make(path + "." + key))
    }

    private func allow(_ allowed: Set<String>) throws {
        if let unknown = keys.subtracting(allowed).sorted().first {
            throw failure({ .unknownField(path: $0) }, unknown)
        }
    }

    private func required<Value>(_ value: Value?, _ key: String) throws -> Value {
        guard let value else { throw failure({ .malformed(path: $0) }, key) }
        return value
    }

    private func entityID() throws -> UUID { try required(id, "id") }

    private func revision() throws -> Revision {
        guard let revision = Revision(rawValue: try required(expected, "expected")) else {
            throw failure({ .invalidValue(path: $0) }, "expected")
        }
        return revision
    }

    private func validTitle(_ raw: String) throws -> EntityTitle {
        do { return try EntityTitle(raw) } catch { throw failure({ .invalidValue(path: $0) }, "title") }
    }

    private func validNote(_ raw: String) throws -> ItemNote {
        do { return try ItemNote(raw) } catch { throw failure({ .invalidValue(path: $0) }, "note") }
    }

    func operation(_ kind: String) throws -> DomainOperation {
        switch kind {
        case "createCollection":
            try allow(["id", "title"])
            return .createCollection(draft: CollectionDraft(
                id: CollectionID(rawValue: try entityID()), title: try validTitle(try required(title, "title"))
            ))
        case "updateCollection":
            try allow(["id", "expected", "title"])
            return .updateCollection(
                id: CollectionID(rawValue: try entityID()), expected: try revision(), title: try validTitle(try required(title, "title"))
            )
        case "archiveCollection":
            try allow(["id", "expected"])
            return .archiveCollection(id: CollectionID(rawValue: try entityID()), expected: try revision())
        case "restoreCollection":
            try allow(["id", "expected"])
            return .restoreCollection(id: CollectionID(rawValue: try entityID()), expected: try revision())
        case "createItem":
            try allow(["id", "collection", "title", "note"])
            return .createItem(draft: ItemDraft(
                id: ItemID(rawValue: try entityID()),
                in: CollectionID(rawValue: try required(collection, "collection")),
                title: try validTitle(try required(title, "title")),
                note: try note.map(validNote) ?? .empty
            ))
        case "updateItem":
            try allow(["id", "expected", "title", "note"])
            let changes: ItemChanges
            do {
                changes = try ItemChanges(title: try title.map(validTitle), note: try note.map(validNote))
            } catch is ValidationError {
                // Neither field is present: the update would change nothing.
                throw failure({ .malformed(path: $0) }, "<title or note>")
            }
            return .updateItem(id: ItemID(rawValue: try entityID()), expected: try revision(), changes: changes)
        case "archiveItem":
            try allow(["id", "expected"])
            return .archiveItem(id: ItemID(rawValue: try entityID()), expected: try revision())
        case "restoreItem":
            try allow(["id", "expected"])
            return .restoreItem(id: ItemID(rawValue: try entityID()), expected: try revision())
        case "setSession":
            // LAB-004. `expected` is absent for a session that was never started.
            try allow(["id", "expected", "running"])
            return .setSession(
                id: SessionID(rawValue: try entityID()),
                expected: expected == nil ? nil : try revision(),
                running: try required(running, "running")
            )
        default:
            throw ScriptFileFailure(error: .unknownField(path: path))
        }
    }
}

private struct FindEntry: Decodable {
    let find: ScriptedFind

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case collection, text, includeArchived, limit, expect
    }

    init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let filter: ItemFilter
        do {
            filter = try ItemFilter(
                collectionID: try container.decodeIfPresent(UUID.self, forKey: .collection).map(CollectionID.init(rawValue:)),
                text: try container.decodeIfPresent(String.self, forKey: .text),
                includeArchived: try container.decodeIfPresent(Bool.self, forKey: .includeArchived) ?? false,
                limit: try container.decodeIfPresent(Int.self, forKey: .limit) ?? 50
            )
        } catch is ValidationError {
            throw ScriptFileFailure(error: .invalidValue(path: ScriptFile.path(decoder.codingPath)))
        }
        let expected = try container.decode([UUID].self, forKey: .expect).map(ItemID.init(rawValue:))
        find = ScriptedFind(filter: filter, expected: expected)
    }
}
