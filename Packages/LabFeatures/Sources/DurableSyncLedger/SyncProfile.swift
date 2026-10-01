import Foundation

/// The optional service profile. iCloud off does not read or write it. A private database is one
/// account's folder. A shared database is one share's folder, readable only by members. Neither
/// path is the public database.
public protocol SyncProfile: Sendable {
    var isEnabled: Bool { get }
    func pull() async throws(LedgerError) -> [MutationEnvelope]
    func push(_ envelopes: [MutationEnvelope]) async throws(LedgerError)
}

/// iCloud is off. `pull` and `push` refuse without touching storage. Callers should notice
/// `isEnabled` and not call them; the refusals are the backstop.
public struct DisabledSyncProfile: SyncProfile {
    public init() {}

    public var isEnabled: Bool { false }

    public func pull() async throws(LedgerError) -> [MutationEnvelope] { throw .icloudDisabled }

    public func push(_ envelopes: [MutationEnvelope]) async throws(LedgerError) { throw .icloudDisabled }
}

/// A directory that stands in for a private or shared CloudKit database.
///
/// Private edits live at `private/<account>/<mutation>.json`. Shared edits live at
/// `shared/<share>/<mutation>.json`. Membership is `shares/<share>/members.json`. One file per
/// mutation, so two devices can add different edits without rewriting each other's files.
public struct FileSyncProfile: SyncProfile {
    public let root: URL
    public let account: AccountID
    public let scope: RecordScope
    public let share: ShareID?

    public init(root: URL, account: AccountID, scope: RecordScope, share: ShareID?) throws(LedgerError) {
        switch scope {
        case .private:
            guard share == nil else { throw .invalidMutation("A private database names no share.") }
        case .shared:
            guard share != nil else { throw .invalidMutation("A shared database names its share.") }
        }
        self.root = root
        self.account = account
        self.scope = scope
        self.share = share
    }

    public var isEnabled: Bool { true }

    /// Adds `account` to the share's member list. Creating the list is how a demo share starts.
    public static func admit(_ account: AccountID, to share: ShareID, in root: URL) throws(LedgerError) {
        let url = membersURL(share: share, root: root)
        var members = (try? readMembers(at: url)) ?? []
        if !members.contains(account) { members.append(account) }
        try writeMembers(members, to: url)
    }

    public func pull() async throws(LedgerError) -> [MutationEnvelope] {
        if scope == .shared { try requireMembership() }
        let folder = envelopeFolder()
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw .storage
        }
        var envelopes: [MutationEnvelope] = []
        for url in urls {
            let data: Data
            do { data = try Data(contentsOf: url) } catch { throw .storage }
            let envelope: MutationEnvelope
            do { envelope = try JSONDecoder().decode(MutationEnvelope.self, from: data) } catch { throw .invalidMutation("The profile holds an edit this build cannot read.") }
            guard envelope.scope == scope, envelope.share == share else { continue }
            if scope == .private, envelope.account != account { continue }
            envelopes.append(envelope)
        }
        return envelopes
    }

    public func push(_ envelopes: [MutationEnvelope]) async throws(LedgerError) {
        if scope == .shared { try requireMembership() }
        let folder = envelopeFolder()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw .storage
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for envelope in envelopes {
            guard envelope.scope == scope, envelope.share == share else {
                throw .invalidMutation("An edit does not belong in this database.")
            }
            if scope == .private, envelope.account != account {
                throw .wrongAccount
            }
            let url = folder.appending(path: "\(envelope.id.rawValue.uuidString).json")
            let data: Data
            do { data = try encoder.encode(envelope) } catch { throw .storage }
            if FileManager.default.fileExists(atPath: url.path) {
                let existing = try? Data(contentsOf: url)
                guard existing == data else { throw .invalidMutation("The profile already holds a different edit with this identifier.") }
                continue
            }
            do {
                try data.write(to: url, options: .withoutOverwriting)
            } catch {
                throw .storage
            }
        }
    }

    private func requireMembership() throws(LedgerError) {
        guard let share else { throw .notAShareMember }
        let members = (try? Self.readMembers(at: Self.membersURL(share: share, root: root))) ?? []
        guard members.contains(account) else { throw .notAShareMember }
    }

    private func envelopeFolder() -> URL {
        switch scope {
        case .private:
            root.appending(path: "private", directoryHint: .isDirectory)
                .appending(path: account.rawValue.uuidString, directoryHint: .isDirectory)
        case .shared:
            root.appending(path: "shared", directoryHint: .isDirectory)
                .appending(path: share!.rawValue.uuidString, directoryHint: .isDirectory)
        }
    }

    private static func membersURL(share: ShareID, root: URL) -> URL {
        root.appending(path: "shares", directoryHint: .isDirectory)
            .appending(path: share.rawValue.uuidString, directoryHint: .isDirectory)
            .appending(path: "members.json")
    }

    private static func readMembers(at url: URL) throws -> [AccountID] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([AccountID].self, from: data)
    }

    private static func writeMembers(_ members: [AccountID], to url: URL) throws(LedgerError) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(members).write(to: url, options: .atomic)
        } catch {
            throw .storage
        }
    }
}
