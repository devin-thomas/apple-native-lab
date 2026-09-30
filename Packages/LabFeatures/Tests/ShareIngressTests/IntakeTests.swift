import Foundation
import LabDomain
import LabStaging
import Testing
import UniformTypeIdentifiers
@testable import ShareIngress

/// LAB-007: one intake of URL, text, image, and movie attachments, staged in order with origins,
/// through real `NSItemProvider`s as the share sheet and pasteboard hand them over.
@Suite struct IntakeTests {
    // MARK: Order and provenance

    @Test func multipleAttachmentsKeepTheirOrderAndProvenance() async throws {
        let lab = try Station()
        let sources = try [
            Providers.link("https://example.org/tide-tables"),
            Providers.text("Harbor walk\nBring the blue notebook."),
            Providers.file(SyntheticMedia.bytes(4_096), type: .png, suggestedName: "Swatch", folder: lab.folder),
            Providers.file(SyntheticMedia.bytes(8_192, seed: 3), type: .quickTimeMovie, suggestedName: "Clip.mov", folder: lab.folder),
        ]
        let attachments = ItemProviderAttachment.attachments(from: sources)
        #expect(attachments.map(\.kind) == [.link, .text, .image, .movie])

        let report = await lab.shareStation.receive(attachments, via: .shareExtension)
        #expect(report.refusal == nil && !report.wasCancelled)
        #expect(report.outcomes.map(\.position) == [1, 2, 3, 4])
        #expect(report.stagedCount == 4)
        #expect(report.summary == "4 items are waiting for review.")

        let snapshot = await lab.inbox.snapshot()
        #expect(snapshot.entries.map(\.id.staging) == report.waitingIDs)
        #expect(snapshot.entries.allSatisfy { $0.source == .shareExtension })
        let origins = snapshot.entries.compactMap(\.origin)
        #expect(origins.count == 4)
        #expect(Set(origins.map(\.batch)) == [report.batch])
        #expect(origins.map(\.position) == [1, 2, 3, 4])
        #expect(origins.allSatisfy { $0.count == 4 && $0.surface == .shareExtension })
        #expect(origins.map(\.contentType) == [UTType.url.identifier, UTType.utf8PlainText.identifier, UTType.png.identifier, UTType.quickTimeMovie.identifier])

        guard case .link(let url, _) = snapshot.entries[0].content else { Issue.record("not a link"); return }
        #expect(url.absoluteString == "https://example.org/tide-tables")
        #expect(snapshot.entries[1].content == .text("Harbor walk\nBring the blue notebook."))
        #expect(snapshot.entries[2].content == .files([InboxFile(name: "Swatch.png", byteCount: 4_096)]))
        #expect(snapshot.entries[3].content == .files([InboxFile(name: "Clip.mov", byteCount: 8_192)]))
        #expect(snapshot.entries.map(\.adoptability) == [
            .ready, .ready, .unavailable(.attachmentsNotAdoptable), .unavailable(.attachmentsNotAdoptable),
        ])
    }

    @Test func aSharedLinkKeepsItsPageTitleWhenTheItemGivesOne() async throws {
        let lab = try Station()
        let item = NSExtensionItem()
        item.attributedContentText = NSAttributedString(string: "Tide tables for the week")
        item.attachments = [Providers.link("https://example.org/tides")]
        let report = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [item]), via: .shareExtension)
        let entry = try #require(await lab.inbox.snapshot().entries.first)
        #expect(report.stagedCount == 1)
        #expect(entry.content == .link(URL(string: "https://example.org/tides")!, title: "Tide tables for the week"))
        #expect(entry.headline == "Tide tables for the week")

        // Several lines are body text, not a title: the link is kept without one.
        #expect(ItemProviderAttachment.usableTitle("Line one\nLine two") == nil)
        #expect(ItemProviderAttachment.usableTitle(String(repeating: "t", count: 1_025)) == nil)
        #expect(ItemProviderAttachment.usableTitle("  ") == nil)
    }

    @Test func thePasteboardPathStagesIntoTheHostFolderAsPaste() async throws {
        let lab = try Station()
        let report = await lab.hostStation.receive(
            ItemProviderAttachment.attachments(from: [Providers.text("A pasted line")]), via: .paste
        )
        let entry = try #require(await lab.inbox.snapshot().entries.first)
        #expect(report.source == .host && report.stagedCount == 1)
        #expect(entry.source == .host)
        #expect(entry.origin?.surface == .paste)
        #expect(entry.source.adapter == .appUI)
    }

    @Test func chosenFilesStageIntoTheHostFolderInOrder() async throws {
        let lab = try Station()
        let first = lab.folder.appending(path: "Field notes.txt")
        let second = lab.folder.appending(path: "Palette.json")
        try Data("Two gulls, one heron.".utf8).write(to: first)
        try Data(#"{"swatches":["amber","cobalt"]}"#.utf8).write(to: second)

        let report = await lab.hostStation.receive(ChosenFile.attachments(from: [first, second]), via: .filePicker)
        #expect(report.stagedCount == 2)
        let entries = await lab.inbox.snapshot().entries
        #expect(entries.map(\.content) == [
            .files([InboxFile(name: "Field notes.txt", byteCount: 21)]),
            .files([InboxFile(name: "Palette.json", byteCount: 31)]),
        ])
        #expect(entries.compactMap(\.origin).map(\.surface) == [.filePicker, .filePicker])
        #expect(entries.compactMap(\.origin?.contentType) == [UTType.plainText.identifier, UTType.json.identifier])
        // The scratch copies are gone; the chosen files are untouched.
        #expect(FileManager.default.fileExists(atPath: first.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: FileManager.default.temporaryDirectory.appending(path: "ShareIngress-\(report.batch)").path(percentEncoded: false)))
    }

    @Test func aCopiedFileReferenceStagesTheFileItself() async throws {
        let lab = try Station()
        let file = lab.folder.appending(path: "Gull count.txt")
        try Data("Fourteen gulls.".utf8).write(to: file)
        let attachments = ItemProviderAttachment.attachments(from: [NSItemProvider(object: file as NSURL)], acceptsFileReferences: true)
        #expect(attachments.map(\.kind) == [.fileReference])
        let report = await lab.hostStation.receive(attachments, via: .paste)
        #expect(report.stagedCount == 1)
        let entry = try #require(await lab.inbox.snapshot().entries.first)
        #expect(entry.content == .files([InboxFile(name: "Gull count.txt", byteCount: 15)]))
        #expect(entry.origin?.contentType == UTType.fileURL.identifier)

        // Through the share sheet, a file reference is refused: another app must not be able to
        // point the extension at files the extension can read.
        let shared = await lab.shareStation.receive(
            ItemProviderAttachment.attachments(from: [NSItemProvider(object: file as NSURL)]), via: .shareExtension
        )
        #expect(shared.outcomes.map(\.result) == [.refused(.unsupportedFileType(file: 1))])
    }

    // MARK: Malformed, oversized, unsupported, hostile

    @Test func malformedAndUnsupportedAttachmentsAreRefusedAloneAndNeverBlockTheRest() async throws {
        let lab = try Station()
        let malformed = try HostileFixtures.data("malformed-utf8.txt")
        let sources = try [
            Providers.text("Before the bad one"),
            Providers.utf8Bytes(malformed),
            Providers.link("file:///etc/hosts"),
            Providers.link("https://user:secret@example.org/"),
            Providers.file(SyntheticMedia.bytes(64), type: .jpeg, suggestedName: "../escape", folder: lab.folder),
            NSItemProvider(item: Data([1, 2, 3]) as NSData, typeIdentifier: UTType.pdf.identifier),
            Providers.text("After the bad ones"),
        ]
        let report = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: sources), via: .shareExtension)
        #expect(report.outcomes.map(\.result.rejection) == [
            nil, .malformedUTF8(offset: try #require(malformed.firstIndex(of: 0xC0))), .unsupportedFileType(file: 3), .linkContainsCredentials,
            .unsafePath(file: 5, .parentReference), .unsupportedFileType(file: 6), nil,
        ])
        #expect(report.stagedCount == 2 && report.refusedCount == 5)
        #expect(report.summary == "2 items are waiting for review, 5 were refused.")
        // Each message names the position and never the content.
        #expect(report.outcomes[4].message == "Item 5: Item 5 has a name that points outside the import (it contains “..”), so the import was refused.")
        #expect(!report.outcomes.map(\.message).joined().contains("escape"))

        let entries = await lab.inbox.snapshot().entries
        #expect(entries.map(\.content) == [.text("Before the bad one"), .text("After the bad ones")])
        #expect(entries.compactMap(\.origin?.position) == [1, 7])
        #expect(lab.leftovers(in: lab.shared, "incoming").isEmpty)

        // The next intake is unaffected.
        let next = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text("Next share")]), via: .shareExtension)
        #expect(next.stagedCount == 1)
    }

    @Test func oversizedTextAndFilesAreRefusedBeforeTheyAreKept() async throws {
        let lab = try Station(limits: ImportLimits(maximumTextBytes: 64, maximumTotalBytes: 1_000))
        let sources = try [
            Providers.text(String(repeating: "a", count: 65)),
            Providers.file(SyntheticMedia.bytes(700), type: .png, suggestedName: "First", folder: lab.folder),
            Providers.file(SyntheticMedia.bytes(700, seed: 9), type: .png, suggestedName: "Second", folder: lab.folder),
            Providers.file(SyntheticMedia.bytes(2_000), type: .png, suggestedName: "Huge", folder: lab.folder),
            Providers.text("small"),
        ]
        let report = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: sources), via: .shareExtension)
        // The text limit is the area's; the file budget spans the whole intake.
        #expect(report.outcomes[0].result.rejection == .textTooLarge(limit: 64))
        #expect(report.outcomes[1].result.stagingID != nil)
        #expect(report.outcomes[2].result.rejection == .totalSizeTooLarge(limit: 1_000))
        #expect(report.outcomes[3].result.rejection == .totalSizeTooLarge(limit: 1_000))
        #expect(report.outcomes[4].result.stagingID != nil)
        #expect(lab.leftovers(in: lab.shared, "incoming").isEmpty)
        #expect(await lab.inbox.snapshot().entries.count == 2)
    }

    @Test func aTextTooLongForANoteStagesButCannotBeAdded() async throws {
        let lab = try Station()
        let note = try String(decoding: HostileFixtures.data("oversized-note.txt"), as: UTF8.self)
        _ = await lab.shareStation.receive(ItemProviderAttachment.attachments(from: [Providers.text(note)]), via: .shareExtension)
        let entry = try #require(await lab.inbox.snapshot().entries.first)
        #expect(entry.adoptability == .unavailable(.textTooLongForNote(limit: ItemNote.maximumLength)))
    }

    @Test func tooManyAttachmentsAreRefusedBeforeAnyIsRead() async throws {
        let lab = try Station()
        let sources = (0..<33).map { _ in CountingSource() }
        let report = await lab.shareStation.receive(sources, via: .shareExtension)
        #expect(report.refusal == .tooManyFiles(limit: 32))
        #expect(report.outcomes.isEmpty)
        #expect(sources.allSatisfy { $0.loadCount == 0 })
        #expect(await lab.inbox.snapshot().entries.isEmpty)

        let empty = await lab.shareStation.receive([], via: .shareExtension)
        #expect(empty.refusal == .emptyContent)
    }

    @Test func aFolderOnlyAcceptsItsOwnSurfaces() async throws {
        let lab = try Station()
        let intoHost = await lab.hostStation.receive([CountingSource()], via: .shareExtension)
        let intoGroup = await lab.shareStation.receive([CountingSource()], via: .paste)
        #expect(intoHost.refusal == .notAuthorized)
        #expect(intoGroup.refusal == .notAuthorized)
        #expect(await lab.inbox.snapshot().entries.isEmpty)
    }

    // MARK: Duplicates

    @Test func sharingTheSameContentAgainIsADuplicateThatKeepsItsFirstOrigin() async throws {
        let lab = try Station()
        let first = await lab.shareStation.receive(
            ItemProviderAttachment.attachments(from: [Providers.text("Same shared note")]), via: .shareExtension
        )
        let second = await lab.shareStation.receive(
            ItemProviderAttachment.attachments(from: [Providers.text("Other"), Providers.text("Same shared note")]), via: .shareExtension
        )
        #expect(second.outcomes.map(\.result) == [.staged(second.waitingIDs[0]), .duplicate(first.waitingIDs[0])])
        #expect(second.summary == "1 item is waiting for review, 1 was already waiting.")

        let entries = await lab.inbox.snapshot().entries
        #expect(entries.count == 2)
        let original = try #require(entries.first { $0.id.staging == first.waitingIDs[0] })
        #expect(original.origin?.batch == first.batch)
        #expect(original.origin?.position == 1)
    }

    // MARK: Diagnostics

    @Test func diagnosticsRecordCountsAndNeverContent() async throws {
        let lab = try Station()
        _ = await lab.shareStation.receive(
            ItemProviderAttachment.attachments(from: [Providers.text("sentinel-7F3A private words"), Providers.link("https://sentinel-7f3a.example/")]),
            via: .shareExtension
        )
        let lines = lab.diagnostics.events.map(\.line)
        #expect(lines.contains { $0.hasPrefix("phase=ingress.receive outcome=succeeded subject=LAB-007") && $0.contains("staged=2") })
        #expect(!lines.joined().lowercased().contains("sentinel"))
    }
}
