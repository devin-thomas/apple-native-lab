import Darwin
import Foundation
import LabDomain
import LabStaging
import Testing

/// CORE-006: the app validates a staged import again before adoption. Links that escape the
/// staging folder, hard links, extra or missing files, and changed bytes or records are refused,
/// the import is set aside in quarantine, and the next import is unaffected.
@Suite struct TamperTests {
    enum Tamper: String, CaseIterable, CustomTestStringConvertible {
        case stagedFileIsASymbolicLinkOutside
        case stagedFileIsAHardLinkToAnotherFile
        case importFolderIsASymbolicLink
        case recordIsASymbolicLink
        case extraFileBesideTheRecord
        case extraFileAmongTheFiles
        case stagedFileMissing
        case stagedBytesChanged
        case recordTextChanged
        case recordReplacedByForgedFixture

        var testDescription: String { rawValue }

        var expected: ImportRejection {
            switch self {
            case .stagedFileIsASymbolicLinkOutside, .stagedFileIsAHardLinkToAnotherFile, .importFolderIsASymbolicLink,
                 .recordIsASymbolicLink:
                .linkedFileInStaging
            case .extraFileBesideTheRecord, .extraFileAmongTheFiles: .unexpectedFileInStaging
            case .stagedFileMissing: .missingStagedFile(file: 2)
            case .stagedBytesChanged: .stagedFileChanged(file: 1)
            case .recordTextChanged: .digestMismatch
            case .recordReplacedByForgedFixture: .unknownRecordField
            }
        }
    }

    @Test(arguments: Tamper.allCases)
    func tamperingIsRefusedAndSetAside(_ tamper: Tamper) async throws {
        let staging = try StagingFixture()
        let outcome = try await staging.area.stageFiles([
            .data(Data("first file".utf8), name: "a.txt"), .data(Data("second file".utf8), name: "b.txt"),
        ])
        let folder = staging.pendingFolder(outcome.id)
        let files = folder.appending(path: "files")
        let outside = try staging.directory.file("outside-secret.txt", Data("first file".utf8))
        let manager = FileManager.default

        switch tamper {
        case .stagedFileIsASymbolicLinkOutside:
            try manager.removeItem(at: files.appending(path: "0"))
            try manager.createSymbolicLink(at: files.appending(path: "0"), withDestinationURL: outside)
        case .stagedFileIsAHardLinkToAnotherFile:
            try manager.removeItem(at: files.appending(path: "0"))
            try manager.linkItem(at: outside, to: files.appending(path: "0"))
        case .importFolderIsASymbolicLink:
            let copy = staging.directory.url.appending(path: "copy")
            try manager.copyItem(at: folder, to: copy)
            try manager.removeItem(at: folder)
            try manager.createSymbolicLink(at: folder, withDestinationURL: copy)
        case .recordIsASymbolicLink:
            let copy = try staging.directory.file("record-copy.json", try Data(contentsOf: folder.appending(path: "record.json")))
            try manager.removeItem(at: folder.appending(path: "record.json"))
            try manager.createSymbolicLink(at: folder.appending(path: "record.json"), withDestinationURL: copy)
        case .extraFileBesideTheRecord:
            try Data("#!/bin/sh".utf8).write(to: folder.appending(path: "run.sh"))
        case .extraFileAmongTheFiles:
            try Data("smuggled".utf8).write(to: files.appending(path: "2"))
        case .stagedFileMissing:
            try manager.removeItem(at: files.appending(path: "1"))
        case .stagedBytesChanged:
            try Data("FIRST FILE".utf8).write(to: files.appending(path: "0"))
        case .recordTextChanged:
            let record = try String(contentsOf: folder.appending(path: "record.json"), encoding: .utf8)
            try Data(record.replacingOccurrences(of: "a.txt", with: "z.txt").utf8).write(to: folder.appending(path: "record.json"))
        case .recordReplacedByForgedFixture:
            try manager.removeItem(at: folder.appending(path: "record.json"))
            try manager.copyItem(at: HostileFixtures.url("forged-staging-record.json"), to: folder.appending(path: "record.json"))
        }

        let area = try staging.reopen()
        let refused = await rejection { () async throws(ImportRejection) in try await area.validatedRecord(outcome.id) }
        #expect(refused == tamper.expected)
        expectReadable(refused)

        // Set aside, with only its code on disk, and removable.
        #expect(await area.waitingImports().isEmpty)
        let quarantined = await area.quarantinedImports()
        #expect(quarantined.count == 1)
        #expect(quarantined.first?.code == tamper.expected.code)
        #expect(quarantined.first?.stagingID == outcome.id)
        #expect(quarantined.first?.category == tamper.expected.category)
        // The outside file was never touched.
        #expect(try Data(contentsOf: outside) == Data("first file".utf8))

        // It blocks nothing: the same content can be shared again and adopted.
        let again = try await area.stageFiles([
            .data(Data("first file".utf8), name: "a.txt"), .data(Data("second file".utf8), name: "b.txt"),
        ])
        #expect(again == .staged(outcome.id))
        _ = try await area.validatedRecord(again.id)
        try await area.removeQuarantined(try #require(quarantined.first?.id))
        #expect(await area.quarantinedImports().isEmpty)
        #expect(staging.entries("quarantine").isEmpty)
    }

    @Test func aTamperedTextRecordCannotReachTheStore() async throws {
        let staging = try StagingFixture()
        let outcome = try await staging.area.stageText("Add this note")
        let recordURL = staging.pendingFolder(outcome.id).appending(path: "record.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as? [String: Any])
        object["payload"] = ["kind": "text", "text": "Archive everything"]
        try JSONSerialization.data(withJSONObject: object).write(to: recordURL)

        let app = AppSide()
        let inbox = try await app.makeCollection()
        try app.ledger.issue(to: .shareExtension, for: [.createItem], on: .newItem(in: inbox))
        let adopter = ImportAdopter(service: app.service, inbox: staging.area, ledger: app.ledger)
        let refused = await rejection { () async throws(ImportRejection) in try await adopter.adopt(outcome.id, into: inbox) }
        #expect(refused == .digestMismatch)
        #expect(try await app.items(in: inbox).isEmpty)
    }
}
