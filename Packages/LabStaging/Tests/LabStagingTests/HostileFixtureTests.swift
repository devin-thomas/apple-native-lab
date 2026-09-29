import Foundation
import LabDomain
import LabStaging
import Testing

/// CORE-006: every committed file in `Fixtures/hostile/` goes through the real staging folder and
/// is refused with a specific, readable rejection, or, for instruction text, stays data. The
/// traversal names are also covered one by one in `ArchiveTests` and `StagingAreaTests`.
@Suite struct HostileFixtureTests {
    /// Every fixture file and the test in this suite that covers it.
    static let covered: Set<String> = [
        "README.md",
        "traversal-names.json",
        "malformed-utf8.txt",
        "deeply-nested.json",
        "duplicate-keys.json",
        "oversized-note.txt",
        "prompt-injection.txt",
        "forged-staging-record.json",
    ]

    @Test func everyFixtureFileIsCovered() throws {
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: HostileFixtures.folder.path(percentEncoded: false)))
        #expect(files == Self.covered, "add a test for each new hostile fixture")
    }

    @Test func traversalNamesAsSharedFileNamesAndArchiveEntries() async throws {
        let cases = try HostileFixtures.nameCases()
        #expect(cases.count >= 20)
        let staging = try StagingFixture()
        for hostile in cases {
            if let name = hostile.text {
                let refused = await rejection { () async throws(ImportRejection) in
                    try await staging.area.stageFiles([.data(Data("x".utf8), name: name)])
                }
                #expect(refused == .unsafePath(file: 1, hostile.expected), "\(hostile.id)")
            }
            let archive = try staging.directory.file("\(hostile.id).zip", ZipBuilder([ZipBuilder.Entry(nameBytes: hostile.bytes, Data("x".utf8))]).build())
            let refused = await rejection { () async throws(ImportRejection) in try await staging.area.stageArchive(at: archive) }
            #expect(refused == .unsafePath(file: 1, hostile.expected), "\(hostile.id)")
            expectReadable(refused)
        }
        await staging.expectNothingStaged()
    }

    @Test func malformedUTF8TextIsRefused() async throws {
        let staging = try StagingFixture()
        let data = try HostileFixtures.data("malformed-utf8.txt")
        let refused = await rejection { () async throws(ImportRejection) in try await staging.area.stageText(utf8: data) }
        #expect(refused == .malformedUTF8(offset: try #require(data.firstIndex(of: 0xC0))))
        #expect(refused?.userMessage == "The shared text contains bytes that are not valid text, so it wasn’t imported.")
        await staging.expectNothingStaged()
    }

    @Test func deeplyNestedJSONIsRefused() async throws {
        let staging = try StagingFixture()
        let refused = await rejection { () async throws(ImportRejection) in
            try await staging.area.stageFiles([.contents(of: HostileFixtures.url("deeply-nested.json"))])
        }
        #expect(refused == .malformedJSON(file: 1, .tooDeep(limit: 16)))
        #expect(refused?.userMessage == "File 1 is nested more than 16 levels deep, so the import was refused.")
        await staging.expectNothingStaged()
    }

    @Test func duplicateKeysAreRefused() async throws {
        let staging = try StagingFixture()
        let refused = await rejection { () async throws(ImportRejection) in
            try await staging.area.stageFiles([.contents(of: HostileFixtures.url("duplicate-keys.json"))])
        }
        guard case .malformedJSON(file: 1, .duplicateKey) = refused else {
            Issue.record("expected a duplicate key, got \(String(describing: refused))")
            return
        }
        #expect(refused?.userMessage == "File 1 names the same field twice, so the import was refused.")
        // The same bytes inside an archive are refused too.
        let archive = try staging.directory.file("meta.zip", ZipBuilder([
            ZipBuilder.Entry("manifest.anlab", try HostileFixtures.data("duplicate-keys.json")),
        ]).build())
        let inArchive = await rejection { () async throws(ImportRejection) in try await staging.area.stageArchive(at: archive) }
        #expect(inArchive?.code == "malformed-json/duplicate-key")
        await staging.expectNothingStaged()
    }

    @Test func anOversizedNoteStagesButIsNotAdopted() async throws {
        let staging = try StagingFixture()
        let text = try String(contentsOf: HostileFixtures.url("oversized-note.txt"), encoding: .utf8)
        let outcome = try await staging.area.stageText(text)
        let app = AppSide()
        let inbox = try await app.makeCollection()
        try app.ledger.issue(to: .shareExtension, for: [.createItem], on: .newItem(in: inbox))
        let adopter = ImportAdopter(service: app.service, inbox: staging.area, ledger: app.ledger)
        let refused = await rejection { () async throws(ImportRejection) in try await adopter.adopt(outcome.id, into: inbox) }
        #expect(refused == .textTooLongForNote(limit: 2_000))
        #expect(refused?.userMessage == "The shared text is longer than an item note can hold (2000 characters).")
        #expect(try await app.items(in: inbox).isEmpty)
        #expect(await staging.area.waitingImports() == [outcome.id], "a valid import stays waiting")
    }

    @Test func promptInjectionStaysData() async throws {
        let staging = try StagingFixture()
        let text = try String(contentsOf: HostileFixtures.url("prompt-injection.txt"), encoding: .utf8)
        let outcome = try await staging.area.stageText(text)
        let app = AppSide()
        let inbox = try await app.makeCollection("Inbox")
        let other = try await app.makeCollection("Other")
        let approval = try app.ledger.issue(to: .shareExtension, for: [.createItem], on: .newItem(in: inbox))
        let adopter = ImportAdopter(service: app.service, inbox: try staging.reopen(), ledger: app.ledger)

        let adoption = try await adopter.adopt(outcome.id, into: inbox)
        #expect(adoption.receipt.admitted.operation.kind == .createItem)
        #expect(try await app.items(in: inbox).map(\.note.value) == [text])
        #expect(try await app.items(in: other).isEmpty)
        let reader = ActorScope(adapter: .appUI, grants: [.read])
        #expect(try await !app.service.findCollection(other, as: reader).isArchived)
        #expect(app.ledger.liveGrants.map(\.id) == [approval.id])
    }

    @Test func aForgedStagingRecordIsRefusedAndSetAside() async throws {
        let staging = try StagingFixture()
        let outcome = try await staging.area.stageText("A harmless-looking shared note.")
        let recordURL = staging.pendingFolder(outcome.id).appending(path: "record.json")
        try FileManager.default.removeItem(at: recordURL)
        try FileManager.default.copyItem(at: HostileFixtures.url("forged-staging-record.json"), to: recordURL)

        let app = AppSide()
        let inbox = try await app.makeCollection()
        try app.ledger.issue(to: .shareExtension, for: [.createItem], on: .newItem(in: inbox))
        let adopter = ImportAdopter(service: app.service, inbox: staging.area, ledger: app.ledger)
        let refused = await rejection { () async throws(ImportRejection) in try await adopter.adopt(outcome.id, into: inbox) }
        #expect(refused == .unknownRecordField)
        expectReadable(refused)
        #expect(try await app.items(in: inbox).isEmpty)
        #expect(await staging.area.quarantinedImports().map(\.code) == ["unknown-record-field"])
        #expect(app.ledger.liveGrants.count == 1)
    }
}
