import Darwin
import Foundation
import LabDomain
import LabStaging
import Synchronization
import Testing

/// Counts how many chunks a source yielded, to prove a refused import read nothing.
final class ReadCounter: Sendable {
    private let count = Mutex(0)

    func file(named name: String, _ data: Data = Data("bytes".utf8)) -> IncomingFile {
        IncomingFile(name: name) {
            self.count.withLock { $0 += 1 }
            return AsyncThrowingStream { continuation in
                continuation.yield(data)
                continuation.finish()
            }
        }
    }

    var reads: Int { count.withLock { $0 } }
}

/// CORE-006: the staging folder a share extension writes and the app reads back.
@Suite struct StagingAreaTests {
    @Test func anExtensionStagesAndTheAppAdoptsLaterFromDisk() async throws {
        let staging = try StagingFixture()
        // The extension: stage, then finish. It never sees the store.
        let outcome = try await staging.area.stageText("Harbor walk\nBring the blue notebook.")
        #expect(outcome == .staged(outcome.id))
        #expect(staging.entries("pending") == [outcome.id.description])
        #expect(staging.entries("pending/\(outcome.id)") == ["record.json"])

        // The app, later, in another process: a new StagingArea on the same folder.
        let app = AppSide()
        let area = try staging.reopen()
        #expect(await area.waitingImports() == [outcome.id])
        let record = try await area.validatedRecord(outcome.id)
        #expect(record.payload == .text("Harbor walk\nBring the blue notebook."))
        let inbox = try await app.makeCollection()
        try app.ledger.issue(to: .shareExtension, for: [.createItem], on: ImportAdopter.grantTarget(into: inbox))
        let adopter = ImportAdopter(service: app.service, inbox: area, ledger: app.ledger)
        let adoption = try await adopter.adopt(outcome.id, into: inbox)

        #expect(adoption.receipt.status == .committed)
        #expect(try await app.items(in: inbox).map(\.title.value) == ["Harbor walk"])
        // The staging record is gone once adopted; the adopted record lives only in the store.
        #expect(staging.entries("pending").isEmpty && staging.entries("incoming").isEmpty)
        #expect(await area.waitingImports().isEmpty)
    }

    @Test func stagingTheSameContentAgainIsIdempotent() async throws {
        let staging = try StagingFixture()
        let first = try await staging.area.stageText("Same note")
        let second = try await staging.area.stageText("Same note")
        #expect(first == .staged(first.id) && second == .duplicate(first.id))
        let files = [IncomingFile.data(Data("abc".utf8), name: "a.txt"), .data(Data("def".utf8), name: "b.txt")]
        let third = try await staging.area.stageFiles(files)
        let fourth = try await staging.area.stageFiles(files)
        #expect(fourth == .duplicate(third.id))
        #expect(staging.entries("pending").count == 2)
        #expect(staging.entries("incoming").isEmpty)
        #expect(staging.diagnostics.events.filter { $0.counts.contains { $0.name == "duplicate" } }.count == 2)
    }

    @Test func filesAreStreamedHashedAndReadBackVerified() async throws {
        let staging = try StagingFixture()
        let big = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let outcome = try await staging.area.stageFiles([
            .data(Data("{\"ok\":true}".utf8), name: "manifest.anlab"),
            .data(big, name: "Photos/beach.raw"),
        ])
        let record = try await staging.area.validatedRecord(outcome.id)
        guard case .files(let files) = record.payload else {
            Issue.record("expected files")
            return
        }
        #expect(files.map(\.path.value) == ["manifest.anlab", "Photos/beach.raw"])
        #expect(files.map(\.byteCount) == [11, big.count])
        #expect(files[1].sha256 == ContentDigest.sha256(big))
        #expect(try await staging.area.contents(of: 1, in: outcome.id) == big)
        #expect(staging.entries("pending/\(outcome.id)/files") == ["0", "1"], "names on disk are positions, never shared names")
    }

    @Test func oversizedPayloadsAreRefusedWhileStreaming() async throws {
        let limits = ImportLimits(maximumTextBytes: 1_024, maximumTotalBytes: 1 << 20)
        let staging = try StagingFixture(limits: limits)
        let chunk = Data(count: 256 * 1_024)
        let endless = IncomingFile(name: "endless.bin") {
            AsyncThrowingStream { continuation in
                for _ in 0..<64 { continuation.yield(chunk) }
                continuation.finish()
            }
        }
        let tooBig = await rejection { () async throws(ImportRejection) in try await staging.area.stageFiles([endless]) }
        #expect(tooBig == .totalSizeTooLarge(limit: 1 << 20))
        expectReadable(tooBig)
        let bigJSON = await rejection { () async throws(ImportRejection) in
            try await staging.area.stageFiles([.data(Data(("[" + String(repeating: "1,", count: 600) + "1]").utf8), name: "meta.json")])
        }
        #expect(bigJSON == .malformedJSON(file: 1, .tooLarge(limit: 1_024)))
        let bigText = await rejection { () async throws(ImportRejection) in
            try await staging.area.stageText(String(repeating: "x", count: 1_025))
        }
        #expect(bigText == .textTooLarge(limit: 1_024))
        let tooMany = await rejection { () async throws(ImportRejection) in
            try await staging.area.stageFiles((0...32).map { .data(Data(), name: "f\($0)") })
        }
        #expect(tooMany == .tooManyFiles(limit: 32))
        await staging.expectNothingStaged()
    }

    @Test(arguments: try HostileFixtures.nameCases().filter { $0.text != nil })
    func aHostileFileNameIsRefusedBeforeAnyByteIsRead(_ hostile: HostileFixtures.NameCase) async throws {
        let staging = try StagingFixture()
        let counter = ReadCounter()
        let refused = await rejection { () async throws(ImportRejection) in
            try await staging.area.stageFiles([counter.file(named: "fine.txt"), counter.file(named: hostile.text!)])
        }
        #expect(refused == .unsafePath(file: 2, hostile.expected))
        expectReadable(refused)
        #expect(counter.reads == 0)
        await staging.expectNothingStaged()
    }

    @Test func aCancelledImportLeavesNothingBehind() async throws {
        let staging = try StagingFixture()
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        continuation.yield(Data(repeating: 7, count: 70_000))
        // A cloud-backed attachment that delivers one chunk and then stalls.
        let slow = IncomingFile(name: "cloud.mov") { stream }
        let area = staging.area
        let task = Task { () async throws -> StagingOutcome in try await area.stageFiles([slow]) }
        for _ in 0..<200 {
            let incoming = staging.entries("incoming")
            if let folder = incoming.first,
               let size = try? FileManager.default.attributesOfItem(
                   atPath: area.root.appending(path: "incoming/\(folder)/files/0").path(percentEncoded: false)
               )[.size] as? Int, size == 70_000 {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(staging.entries("incoming").count == 1, "the import was underway")
        task.cancel()
        await #expect(throws: ImportRejection.cancelled) { try await task.value }
        continuation.finish()
        await staging.expectNothingStaged()
        #expect(staging.diagnostics.events.last?.outcome == .cancelled)

        // The next import is unaffected.
        let next = try await staging.area.stageText("After the cancelled one")
        #expect(await staging.area.waitingImports() == [next.id])
    }

    @Test func aTaskCancelledBeforeStagingStagesNothing() async throws {
        let staging = try StagingFixture()
        let area = staging.area
        let task = Task { () async throws -> StagingOutcome in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await area.stageFiles([.data(Data("x".utf8), name: "x.txt")])
        }
        await #expect(throws: ImportRejection.cancelled) { try await task.value }
        await staging.expectNothingStaged()
    }

    @Test func anAbandonedIncomingFolderIsSweptAndARecentOneIsKept() async throws {
        let staging = try StagingFixture()
        let incoming = staging.area.root.appending(path: "incoming")
        let abandoned = incoming.appending(path: UUID().uuidString)
        let recent = incoming.appending(path: UUID().uuidString)
        for folder in [abandoned, recent] {
            try FileManager.default.createDirectory(at: folder.appending(path: "files"), withIntermediateDirectories: true)
            try Data("partial".utf8).write(to: folder.appending(path: "files/0"))
        }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-2 * 3_600)], ofItemAtPath: abandoned.path(percentEncoded: false))
        _ = try staging.reopen()
        #expect(staging.entries("incoming") == [recent.lastPathComponent])
        _ = try await staging.area.stageText("Unblocked")
    }

    @Test func discardRemovesAWaitingImport() async throws {
        let staging = try StagingFixture()
        let outcome = try await staging.area.stageLink(try #require(URL(string: "https://example.com/")), title: "Example")
        try await staging.area.discard(outcome.id)
        await staging.expectNothingStaged()
        try await staging.area.discard(outcome.id)
        await #expect(throws: ImportRejection.notFound) { try await staging.area.validatedRecord(outcome.id) }
    }

    @Test func sourcesMustBeOrdinaryFiles() async throws {
        let staging = try StagingFixture()
        let folder = staging.directory.url.appending(path: "a-folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fifo = staging.directory.url.appending(path: "pipe")
        #expect(mkfifo(fifo.path(percentEncoded: false), 0o600) == 0)
        for source in [folder, fifo] {
            let refused = await rejection { () async throws(ImportRejection) in
                try await staging.area.stageFiles([.contents(of: source, name: "item.bin")])
            }
            #expect(refused == .unsupportedFileType(file: 1))
        }
        let missing = await rejection { () async throws(ImportRejection) in
            try await staging.area.stageFiles([.contents(of: staging.directory.url.appending(path: "missing"), name: "m.bin")])
        }
        #expect(missing == .unreadableSource(file: 1))
        let real = try staging.directory.file("real.txt", Data("chosen by a person".utf8))
        let outcome = try await staging.area.stageFiles([.contents(of: real)])
        #expect(try await staging.area.contents(of: 0, in: outcome.id) == Data("chosen by a person".utf8))
        await #expect(throws: ImportRejection.notFound) { try await staging.area.contents(of: 1, in: outcome.id) }
    }

    @Test func aStagingFolderWhoseSubfolderIsALinkIsRefused() throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.appending(path: "Staging")
        let elsewhere = directory.url.appending(path: "Elsewhere")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "pending"), withDestinationURL: elsewhere)
        #expect(throws: ImportRejection.linkedFileInStaging) { try StagingArea(root: root) }
    }
}
