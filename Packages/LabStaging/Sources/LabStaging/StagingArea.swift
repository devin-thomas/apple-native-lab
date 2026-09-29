import Dispatch
import Foundation
import LabDomain

/// Identifies one import set aside in quarantine.
public struct QuarantineID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public var description: String { rawValue.uuidString }
}

/// An import that failed validation and was set aside. It never blocks a later import, and a
/// person can remove it.
public struct QuarantinedImport: Hashable, Sendable {
    public let id: QuarantineID
    /// The staging ID it had, when it had a valid one.
    public let stagingID: StagingID?
    /// The rejection's stable code, such as `unsafe-path/parent-reference`.
    public let code: String?
    public let category: DiagnosticCategory?
}

/// The staging folder: where shared content waits, outside the store, until the app adopts it.
///
/// A share extension opens a `StagingArea` on a folder in the App Group container, stages what
/// was shared, and finishes. The app opens another `StagingArea` on the same folder, lists what
/// is waiting, validates it again with `validatedRecord(_:)`, and adopts it with `ImportAdopter`.
///
/// Layout, all inside the root:
///
/// - `incoming/<random>/`: an import being written. Nothing reads it. A failed or cancelled
///   import deletes its folder, and folders an interrupted process left behind are swept.
/// - `pending/<staging ID>/record.json` and `files/0`, `files/1`, …: a complete import, moved into
///   place with one exclusive rename. The staging ID derives from the content, so a second copy
///   of the same content finds the name taken and becomes a duplicate.
/// - `quarantine/<random>/`: an import that failed validation, with `reason.json` holding only
///   its rejection code.
///
/// Staged bytes are stored under their position, never under their shared name, so a hostile
/// name is never a path here. Reading back does not follow links, refuses hard-linked files,
/// checks every file's size and SHA-256, and refuses any file the record does not list.
///
/// On iOS, watchOS, and tvOS new folders and files use `completeUnlessOpen` data protection. The
/// actor runs on its own serial queue because file work blocks.
public actor StagingArea: StagingInbox {
    public nonisolated let limits: ImportLimits
    /// The root with every link resolved.
    public nonisolated let root: URL
    /// Incoming folders older than this are treated as abandoned by a stopped process.
    public static let abandonedAfter: TimeInterval = 60 * 60

    private let incoming: URL
    private let pending: URL
    private let quarantine: URL
    private let diagnostics: DiagnosticsLog?
    private let subject: DiagnosticSubject?
    private let now: @Sendable () -> Date
    private let queue: DispatchSerialQueue

    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// Opens or creates the staging folder at `root`, and sweeps abandoned incoming folders.
    public init(
        root: URL,
        limits: ImportLimits = .standard,
        diagnostics: DiagnosticsLog? = nil,
        subject: DiagnosticSubject? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws(ImportRejection) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: Self.protection)
        } catch {
            throw .stagingUnavailable
        }
        guard let resolved = SafeFile.resolvedPath(of: root) else { throw .stagingUnavailable }
        let base = URL(filePath: resolved, directoryHint: .isDirectory)
        for name in ["incoming", "pending", "quarantine"] {
            let folder = base.appending(path: name, directoryHint: .isDirectory)
            switch SafeFile.kind(of: folder) {
            case .directory: continue
            case nil:
                do { try fileManager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: Self.protection) } catch {
                    throw .stagingUnavailable
                }
            case .symbolicLink, .regular, .other:
                throw .linkedFileInStaging
            }
        }
        self.limits = limits
        self.root = base
        incoming = base.appending(path: "incoming", directoryHint: .isDirectory)
        pending = base.appending(path: "pending", directoryHint: .isDirectory)
        quarantine = base.appending(path: "quarantine", directoryHint: .isDirectory)
        self.diagnostics = diagnostics
        self.subject = subject
        self.now = now
        queue = DispatchSerialQueue(label: "LabStaging.StagingArea")
        Self.removeAbandoned(in: incoming, olderThan: now().addingTimeInterval(-Self.abandonedAfter))
    }

    // MARK: Staging (extension side)

    /// Stages shared text.
    public func stageText(_ text: String) throws(ImportRejection) -> StagingOutcome {
        try recorded("import.stage.text") { () throws(ImportRejection) in
            let record = try StagingRecord(payload: .text(text), stagedAt: now(), limits: limits)
            let outcome = try commit(record)
            return (outcome, record.byteCount, 0)
        }
    }

    /// Stages shared text that arrived as bytes. Ill-formed UTF-8 is refused, not repaired.
    public func stageText(utf8 data: Data) throws(ImportRejection) -> StagingOutcome {
        try recorded("import.stage.text") { () throws(ImportRejection) in
            let record = try StagingRecord.text(utf8: data, stagedAt: now(), limits: limits)
            let outcome = try commit(record)
            return (outcome, record.byteCount, 0)
        }
    }

    /// Stages a shared web link and, when the source gave one, its page title.
    public func stageLink(_ url: URL, title: String? = nil) throws(ImportRejection) -> StagingOutcome {
        try recorded("import.stage.link") { () throws(ImportRejection) in
            let record = try StagingRecord(payload: .link(url, title: title), stagedAt: now(), limits: limits)
            let outcome = try commit(record)
            return (outcome, record.byteCount, 0)
        }
    }

    /// Stages shared files. Every name is validated before any byte is read, and sizes are
    /// enforced while the bytes stream in. JSON files (`.json`, `.anlab`) must pass `StrictJSON`.
    public func stageFiles(_ files: [IncomingFile]) async throws(ImportRejection) -> StagingOutcome {
        let start = ContinuousClock.now
        do {
            let (outcome, record) = try await stageFilesChecked(files)
            let isDuplicate = if case .duplicate = outcome { true } else { false }
            succeed("import.stage.files", start, bytes: record.byteCount, files: record.fileCount, duplicate: isDuplicate)
            return outcome
        } catch {
            diagnostics?.record("import.stage.files", failure: error, subject: subject, duration: ContinuousClock.now - start)
            throw error
        }
    }

    /// Stages a ZIP archive by expanding it into staging. Its directory must pass
    /// `ArchivePolicy` before anything expands, every entry is bounded by its declared size while
    /// it streams, and every expanded file is checked for a nested archive and, for JSON, strict
    /// syntax. A refused archive leaves nothing behind.
    public func stageArchive(at url: URL) throws(ImportRejection) -> StagingOutcome {
        try recorded("import.stage.archive") { () throws(ImportRejection) in
            let record = try stageArchiveChecked(url)
            return (record.outcome, record.byteCount, record.fileCount)
        }
    }

    // MARK: Reading back (app side)

    /// Waiting imports, oldest first.
    public func waitingImports() -> [StagingID] {
        let names = (try? FileManager.default.contentsOfDirectory(
            at: pending, includingPropertiesForKeys: [.creationDateKey], options: []
        )) ?? []
        return names.compactMap { url -> (StagingID, Date)? in
            guard let uuid = UUID(uuidString: url.lastPathComponent), uuid.uuidString == url.lastPathComponent else { return nil }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return (StagingID(rawValue: uuid), created)
        }
        .sorted { $0.1 == $1.1 ? $0.0.description < $1.0.description : $0.1 < $1.1 }
        .map(\.0)
    }

    public func validatedRecord(_ id: StagingID) throws(ImportRejection) -> StagingRecord {
        let folder = pending.appending(path: id.description, directoryHint: .isDirectory)
        guard SafeFile.kind(of: folder) != nil else { throw .notFound }
        let start = ContinuousClock.now
        do throws(ImportRejection) {
            let record = try verify(folder, id: id)
            succeed("import.validate", start, bytes: record.byteCount, files: record.fileCount)
            return record
        } catch {
            diagnostics?.record("import.validate", failure: error, subject: subject, duration: ContinuousClock.now - start)
            setAside(folder, stagingID: id, reason: error)
            throw error
        }
    }

    /// The verified bytes of one staged file, for a host that shows or adopts attachments.
    /// The whole record is validated again first, and the file is checked as it is read. The
    /// result is held in memory, so use it for files a host can hold.
    public func contents(of file: Int, in id: StagingID) throws(ImportRejection) -> Data {
        let record = try validatedRecord(id)
        guard case .files(let files) = record.payload, files.indices.contains(file) else { throw .notFound }
        let url = pending.appending(path: "\(id)/files/\(file)", directoryHint: .notDirectory)
        return try readVerified(url, file: files[file], position: file + 1, keep: true)
    }

    public func markAdopted(_ id: StagingID) throws(ImportRejection) {
        try remove(pending.appending(path: id.description, directoryHint: .isDirectory))
    }

    /// Removes a waiting import a person chose not to add.
    public func discard(_ id: StagingID) throws(ImportRejection) {
        try remove(pending.appending(path: id.description, directoryHint: .isDirectory))
    }

    public func quarantinedImports() -> [QuarantinedImport] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: quarantine, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder -> QuarantinedImport? in
            guard let uuid = UUID(uuidString: folder.lastPathComponent) else { return nil }
            let reason = Self.readReason(folder.appending(path: "reason.json"))
            return QuarantinedImport(
                id: QuarantineID(rawValue: uuid),
                stagingID: reason.stagingID,
                code: reason.code,
                category: reason.category
            )
        }
        .sorted { $0.id.description < $1.id.description }
    }

    public func removeQuarantined(_ id: QuarantineID) throws(ImportRejection) {
        try remove(quarantine.appending(path: id.description, directoryHint: .isDirectory))
    }

    /// Removes incoming folders an interrupted process left behind. `init` runs it too.
    public func sweepAbandonedImports() {
        Self.removeAbandoned(in: incoming, olderThan: now().addingTimeInterval(-Self.abandonedAfter))
    }

    // MARK: Staging internals

    private func stageFilesChecked(_ files: [IncomingFile]) async throws(ImportRejection) -> (StagingOutcome, StagingRecord) {
        guard !files.isEmpty else { throw .noFiles }
        guard files.count <= limits.maximumFiles else { throw .tooManyFiles(limit: limits.maximumFiles) }
        var names = StagedPathSet()
        var paths: [StagedPath] = []
        for (index, file) in files.enumerated() {
            let path: StagedPath
            do { path = try StagedPath(file.name, limits: limits) } catch { throw .unsafePath(file: index + 1, error) }
            guard names.insert(path, isDirectory: false) else { throw .duplicatePath(file: index + 1) }
            paths.append(path)
        }
        let folder = try makeIncomingFolder()
        do throws(ImportRejection) {
            var staged: [StagedFile] = []
            var total = 0
            for (index, file) in files.enumerated() {
                let position = index + 1
                var writer = try StagedFileWriter(
                    url: folder.appending(path: "files/\(index)"), path: paths[index], position: position, limits: limits,
                    budget: limits.maximumTotalBytes - total, checkNestedArchive: false
                )
                do {
                    for try await chunk in file.chunks() {
                        guard !Task.isCancelled else { throw ImportRejection.cancelled }
                        try writer.append(chunk, overflow: .totalSizeTooLarge(limit: limits.maximumTotalBytes))
                    }
                } catch let rejection as ImportRejection {
                    throw rejection
                } catch is CancellationError {
                    throw .cancelled
                } catch SourceError.notRegularFile {
                    throw .unsupportedFileType(file: position)
                } catch {
                    throw .unreadableSource(file: position)
                }
                // A stream ends quietly when its consumer is cancelled, so an early end is not a
                // complete file.
                guard !Task.isCancelled else { throw .cancelled }
                let file = try writer.finish()
                total += file.byteCount
                staged.append(file)
            }
            let record = try StagingRecord(payload: .files(staged), stagedAt: now(), limits: limits)
            let outcome = try place(folder, record: record)
            return (outcome, record)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func stageArchiveChecked(_ url: URL) throws(ImportRejection) -> (outcome: StagingOutcome, byteCount: Int, fileCount: Int) {
        let source: (handle: FileHandle, size: Int)
        do {
            source = try SafeFile.openSource(url)
        } catch .notRegularFile {
            throw .unsupportedFileType(file: 1)
        } catch {
            throw .unreadableSource(file: 1)
        }
        var reader = try ZipReader(handle: source.handle, size: source.size, limits: limits)
        let plan = try ArchivePolicy.plan(reader.entries.map(\.descriptor), limits: limits)
        try reader.verifyLayout()
        let folder = try makeIncomingFolder()
        do throws(ImportRejection) {
            var staged: [StagedFile] = []
            for (index, planned) in plan.files.enumerated() {
                guard !Task.isCancelled else { throw .cancelled }
                let position = planned.entryIndex + 1
                var writer = try StagedFileWriter(
                    url: folder.appending(path: "files/\(index)"), path: planned.path, position: position, limits: limits,
                    budget: planned.declaredSize, checkNestedArchive: true
                )
                try reader.extract(reader.entries[planned.entryIndex], position: position) { data throws(ImportRejection) in
                    try writer.append(data, overflow: .expandsBeyondDeclaredSize(file: position))
                }
                staged.append(try writer.finish())
            }
            if staged.isEmpty { throw .noFiles }
            let record = try StagingRecord(payload: .files(staged), stagedAt: now(), limits: limits)
            let outcome = try place(folder, record: record)
            return (outcome, record.byteCount, record.fileCount)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Writes a text or link record through an incoming folder, so every record reaches
    /// `pending/` the same way.
    private func commit(_ record: StagingRecord) throws(ImportRejection) -> StagingOutcome {
        let folder = try makeIncomingFolder()
        do throws(ImportRejection) {
            return try place(folder, record: record)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func makeIncomingFolder() throws(ImportRejection) -> URL {
        let folder = incoming.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(
                at: folder.appending(path: "files", directoryHint: .isDirectory),
                withIntermediateDirectories: true,
                attributes: Self.protection
            )
        } catch {
            throw .stagingUnavailable
        }
        return folder
    }

    /// Writes `record.json`, flushes it, and moves the folder into `pending/` under the record's
    /// ID with one exclusive rename. If that name is taken, the same content is already waiting.
    private func place(_ folder: URL, record: StagingRecord) throws(ImportRejection) -> StagingOutcome {
        if record.fileCount == 0 {
            try? FileManager.default.removeItem(at: folder.appending(path: "files", directoryHint: .isDirectory))
        }
        do {
            let handle = try SafeFile.createExclusively(folder.appending(path: "record.json"))
            try handle.write(contentsOf: record.encoded())
            try handle.synchronize()
            try handle.close()
        } catch {
            throw .stagingUnavailable
        }
        let destination = pending.appending(path: record.id.description, directoryHint: .isDirectory)
        let moved: Bool
        do { moved = try SafeFile.moveExclusively(folder, to: destination) } catch { throw .stagingUnavailable }
        guard moved else {
            try? FileManager.default.removeItem(at: folder)
            return .duplicate(record.id)
        }
        return .staged(record.id)
    }

    // MARK: Verification internals

    private func verify(_ folder: URL, id: StagingID) throws(ImportRejection) -> StagingRecord {
        guard SafeFile.kind(of: folder) == .directory else { throw .linkedFileInStaging }
        guard SafeFile.resolvedPath(of: folder) == SafeFile.path(folder) else {
            throw .linkedFileInStaging
        }
        let recordData: Data
        do {
            let opened = try SafeFile.openStagedFile(folder.appending(path: "record.json"))
            guard opened.size <= limits.maximumRecordBytes else { throw ImportRejection.recordTooLarge(limit: limits.maximumRecordBytes) }
            recordData = try opened.handle.read(upToCount: limits.maximumRecordBytes + 1) ?? Data()
        } catch let rejection as ImportRejection {
            throw rejection
        } catch SafeFile.Failure.linked {
            throw .linkedFileInStaging
        } catch SafeFile.Failure.missing {
            throw .unexpectedFileInStaging
        } catch SafeFile.Failure.notRegularFile {
            throw .unexpectedFileInStaging
        } catch {
            throw .stagingUnavailable
        }
        let record = try StagingRecord(decoding: recordData, limits: limits)
        guard record.id == id else { throw .digestMismatch }

        let expected: Set<String> = record.fileCount > 0 ? ["record.json", "files"] : ["record.json"]
        guard Set(try listing(folder)) == expected else { throw .unexpectedFileInStaging }
        guard case .files(let files) = record.payload else { return record }

        let filesFolder = folder.appending(path: "files", directoryHint: .isDirectory)
        guard SafeFile.kind(of: filesFolder) == .directory else { throw .linkedFileInStaging }
        let names = try listing(filesFolder)
        guard Set(names) == Set(files.indices.map(String.init)) else {
            throw names.count < files.count ? .missingStagedFile(file: names.count + 1) : .unexpectedFileInStaging
        }
        for (index, file) in files.enumerated() {
            let url = filesFolder.appending(path: String(index), directoryHint: .notDirectory)
            guard let resolved = SafeFile.resolvedPath(of: url), resolved.hasPrefix(root.path(percentEncoded: false)) else {
                throw .linkedFileInStaging
            }
            try readVerified(url, file: file, position: index + 1)
        }
        return record
    }

    /// Reads one staged file without following links, in chunks, and checks its size, digest,
    /// and, for JSON, its syntax. Only JSON (bounded by the text limit) and bytes the caller asks
    /// to keep are held in memory, so verifying large media does not allocate its size.
    @discardableResult
    private func readVerified(_ url: URL, file: StagedFile, position: Int, keep: Bool = false) throws(ImportRejection) -> Data {
        let opened: (handle: FileHandle, size: Int)
        do {
            opened = try SafeFile.openStagedFile(url)
        } catch .linked {
            throw .linkedFileInStaging
        } catch .missing {
            throw .missingStagedFile(file: position)
        } catch .notRegularFile {
            throw .unexpectedFileInStaging
        } catch {
            throw .stagingUnavailable
        }
        guard opened.size == file.byteCount else { throw .stagedFileChanged(file: position) }
        let isJSON = StagedFileWriter.isJSON(file.path)
        if isJSON, file.byteCount > limits.maximumTextBytes {
            throw .malformedJSON(file: position, .tooLarge(limit: limits.maximumTextBytes))
        }
        var hasher = ContentHasher()
        var kept = Data()
        var count = 0
        while true {
            let chunk: Data
            do { chunk = try opened.handle.read(upToCount: BoundedInflater.chunkSize) ?? Data() } catch { throw .stagingUnavailable }
            if chunk.isEmpty { break }
            count += chunk.count
            guard count <= file.byteCount else { throw .stagedFileChanged(file: position) }
            hasher.update(chunk)
            if keep || isJSON { kept.append(chunk) }
        }
        guard count == file.byteCount, hasher.finalize() == file.sha256 else { throw .stagedFileChanged(file: position) }
        if isJSON {
            do {
                try StrictJSON.validate(kept, maximumDepth: limits.maximumNestingDepth, maximumBytes: limits.maximumTextBytes)
            } catch {
                throw .malformedJSON(file: position, error)
            }
        }
        return keep ? kept : Data()
    }

    private func listing(_ folder: URL) throws(ImportRejection) -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: SafeFile.path(folder))
        } catch {
            throw .stagingUnavailable
        }
    }

    /// Moves a failed import into quarantine with a reason file that holds only its code.
    private func setAside(_ folder: URL, stagingID: StagingID, reason: ImportRejection) {
        guard reason != .notFound, reason != .stagingUnavailable else { return }
        let destination = quarantine.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false, attributes: Self.protection)
            try FileManager.default.moveItem(at: folder, to: destination.appending(path: "import", directoryHint: .isDirectory))
            let reasonFile = QuarantineReason(stagingID: stagingID.description, code: reason.code, category: reason.category.rawValue)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(reasonFile).write(to: destination.appending(path: "reason.json"), options: [.withoutOverwriting])
            diagnostics?.record("import.quarantine", outcome: .rejected, subject: subject, category: reason.category)
        } catch {
            // If the move failed, the import stays in pending/ and is refused again next time;
            // it still cannot block other imports, which use their own folders.
            diagnostics?.record("import.quarantine", outcome: .failed, subject: subject, category: .unavailable)
        }
    }

    private func remove(_ folder: URL) throws(ImportRejection) {
        guard SafeFile.kind(of: folder) != nil else { return }
        do { try FileManager.default.removeItem(at: folder) } catch { throw .stagingUnavailable }
    }

    // MARK: Diagnostics

    private func recorded(
        _ phase: DiagnosticName,
        _ body: () throws(ImportRejection) -> (StagingOutcome, Int, Int)
    ) throws(ImportRejection) -> StagingOutcome {
        let start = ContinuousClock.now
        do {
            let (outcome, bytes, files) = try body()
            let isDuplicate = if case .duplicate = outcome { true } else { false }
            succeed(phase, start, bytes: bytes, files: files, duplicate: isDuplicate)
            return outcome
        } catch {
            diagnostics?.record(phase, failure: error, subject: subject, duration: ContinuousClock.now - start)
            throw error
        }
    }

    private func succeed(_ phase: DiagnosticName, _ start: ContinuousClock.Instant, bytes: Int, files: Int, duplicate: Bool = false) {
        var counts: [DiagnosticName: Int] = ["bytes": bytes, "files": files]
        if duplicate { counts["duplicate"] = 1 }
        diagnostics?.record(phase, outcome: .succeeded, subject: subject, duration: ContinuousClock.now - start, counts: counts)
    }

    // MARK: Static helpers

    private static var protection: [FileAttributeKey: Any]? {
        #if os(macOS)
        nil
        #else
        [.protectionKey: FileProtectionType.completeUnlessOpen]
        #endif
    }

    private static func removeAbandoned(in folder: URL, olderThan cutoff: Date) {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: []
        )) ?? []
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff { try? FileManager.default.removeItem(at: entry) }
        }
    }

    private static func readReason(_ url: URL) -> (stagingID: StagingID?, code: String?, category: DiagnosticCategory?) {
        guard let opened = try? SafeFile.openStagedFile(url), opened.size <= 1_024,
              let data = try? opened.handle.read(upToCount: 1_025),
              (try? StrictJSON.validate(data, maximumDepth: 1, maximumBytes: 1_024)) != nil,
              let reason = try? JSONDecoder().decode(QuarantineReason.self, from: data)
        else { return (nil, nil, nil) }
        let stagingID = UUID(uuidString: reason.stagingID).map(StagingID.init(rawValue:))
        return (stagingID, reason.code, DiagnosticCategory(rawValue: reason.category))
    }
}

private struct QuarantineReason: Codable {
    let stagingID: String
    let code: String
    let category: String
}

/// Streams one file into staging: bounded, hashed, and checked as it goes.
struct StagedFileWriter {
    private let handle: FileHandle
    private let path: StagedPath
    private let position: Int
    private let limits: ImportLimits
    private let budget: Int
    private let checkNestedArchive: Bool
    private var hasher = ContentHasher()
    private var count = 0
    private var prefix: [UInt8] = []
    private var json: Data?

    init(url: URL, path: StagedPath, position: Int, limits: ImportLimits, budget: Int, checkNestedArchive: Bool) throws(ImportRejection) {
        do { handle = try SafeFile.createExclusively(url) } catch { throw .stagingUnavailable }
        self.path = path
        self.position = position
        self.limits = limits
        self.budget = budget
        self.checkNestedArchive = checkNestedArchive
        json = Self.isJSON(path) ? Data() : nil
    }

    static func isJSON(_ path: StagedPath) -> Bool {
        ["json", "anlab"].contains(path.pathExtension)
    }

    /// Adds bytes, refusing with `overflow` once the file would pass its budget.
    mutating func append(_ data: Data, overflow: ImportRejection) throws(ImportRejection) {
        guard data.count <= budget - count else { throw overflow }
        count += data.count
        hasher.update(data)
        if prefix.count < 512 { prefix.append(contentsOf: data.prefix(512 - prefix.count)) }
        if json != nil {
            guard count <= limits.maximumTextBytes else {
                throw .malformedJSON(file: position, .tooLarge(limit: limits.maximumTextBytes))
            }
            json?.append(data)
        }
        do { try handle.write(contentsOf: data) } catch { throw .stagingUnavailable }
    }

    /// Checks the whole file and flushes it to disk.
    func finish() throws(ImportRejection) -> StagedFile {
        if checkNestedArchive, ArchivePolicy.looksLikeArchive(prefix) { throw .nestedArchive(file: position) }
        if let json {
            do {
                try StrictJSON.validate(json, maximumDepth: limits.maximumNestingDepth, maximumBytes: limits.maximumTextBytes)
            } catch {
                throw .malformedJSON(file: position, error)
            }
        }
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            throw .stagingUnavailable
        }
        return StagedFile(path: path, byteCount: count, sha256: hasher.finalize())
    }
}
