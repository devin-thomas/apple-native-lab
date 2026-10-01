import Foundation

enum LedgerCoding {
    static func rejectUnknownFields(in decoder: any Decoder, allowed: Set<String>) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        for key in container.allKeys where !allowed.contains(key.stringValue) {
            throw LedgerError.invalidDocument("The document has a field this build does not accept.")
        }
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) { nil }
}

enum LedgerJSON {
    static func data(_ value: some Encodable) throws(LedgerError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do { return try encoder.encode(value) } catch { throw .storage }
    }

    static func line(_ value: some Encodable) throws(LedgerError) -> Data {
        var encoded = try data(value)
        encoded.append(0x0A)
        return encoded
    }
}

/// Append-only mutation log plus the set of mutations already materialized.
///
/// An envelope is durable once its line is synchronized. A crash before the applied mark leaves
/// it to be materialized on the next open. A refused local edit removes its line again, so a
/// denial is not replayed later as if the person had confirmed it.
struct WriteAheadLog {
    private let envelopesURL: URL
    private let appliedURL: URL
    private(set) var envelopes: [MutationEnvelope] = []
    private var applied: Set<MutationID> = []

    init(directory: URL) throws(LedgerError) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .storage
        }
        envelopesURL = directory.appending(path: "envelopes.ndjson")
        appliedURL = directory.appending(path: "applied.txt")
        try load()
    }

    func contains(_ id: MutationID) -> Bool { envelopes.contains { $0.id == id } }

    func isApplied(_ id: MutationID) -> Bool { applied.contains(id) }

    func envelopes(for record: RecordID) -> [MutationEnvelope] {
        envelopes.filter { $0.record == record }
    }

    var records: [RecordID] {
        var seen: [RecordID] = []
        for envelope in envelopes where !seen.contains(envelope.record) {
            seen.append(envelope.record)
        }
        return seen
    }

    mutating func append(_ envelope: MutationEnvelope) throws(LedgerError) {
        guard !contains(envelope.id) else { return }
        let line = try LedgerJSON.line(envelope)
        do {
            if !FileManager.default.fileExists(atPath: envelopesURL.path) {
                FileManager.default.createFile(atPath: envelopesURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: envelopesURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.synchronize()
        } catch {
            throw .storage
        }
        envelopes.append(envelope)
    }

    mutating func markApplied(_ id: MutationID) throws(LedgerError) {
        guard contains(id), !applied.contains(id) else { return }
        let line = Data((id.rawValue.uuidString + "\n").utf8)
        do {
            if !FileManager.default.fileExists(atPath: appliedURL.path) {
                FileManager.default.createFile(atPath: appliedURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: appliedURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.synchronize()
        } catch {
            throw .storage
        }
        applied.insert(id)
    }

    mutating func removeUnapplied(_ id: MutationID) throws(LedgerError) {
        guard contains(id), !applied.contains(id) else { return }
        envelopes.removeAll { $0.id == id }
        var data = Data()
        for envelope in envelopes {
            data.append(try LedgerJSON.line(envelope))
        }
        do {
            try data.write(to: envelopesURL, options: .atomic)
        } catch {
            throw .storage
        }
    }

    private mutating func load() throws(LedgerError) {
        if FileManager.default.fileExists(atPath: envelopesURL.path) {
            let data: Data
            do { data = try Data(contentsOf: envelopesURL) } catch { throw .storage }
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                do {
                    envelopes.append(try JSONDecoder().decode(MutationEnvelope.self, from: Data(line.utf8)))
                } catch {
                    throw .invalidMutation("The ledger holds an edit this build cannot read.")
                }
            }
        }
        if FileManager.default.fileExists(atPath: appliedURL.path) {
            let data: Data
            do { data = try Data(contentsOf: appliedURL) } catch { throw .storage }
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let id = MutationID(uuidString: String(line)) else {
                    throw .invalidMutation("The ledger holds an applied mark this build cannot read.")
                }
                applied.insert(id)
            }
        }
    }
}
