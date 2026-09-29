import Darwin
import Foundation
@testable import LabDemo
import LabDomain
import LabSupport
import Testing

/// CORE-009 criterion 3: an export does not include adjacent directories or hidden source media.
@Suite struct ConfinementTests {
    private let exporter = EvidenceExporter(now: { fixedDate })

    /// A source folder `root/` with an allowed file, and a private file beside the root.
    private struct Layout {
        let temporary: TemporaryFolder
        let root: URL

        init() throws {
            temporary = try TemporaryFolder()
            root = try temporary.folder("root")
            try temporary.write("allowed\n", to: "root/allowed.txt")
            try temporary.write("PRIVATE-NEIGHBOR\n", to: "private.txt")
            try temporary.write("PRIVATE-FOLDER\n", to: "neighbor/inside.txt")
        }
    }

    private func reason(_ artifact: ExportArtifact) throws -> String? {
        let preview = try exporter.preview(EvidenceExportRequest(title: "Confinement", artifacts: [artifact], provenance: testProvenance))
        #expect(!preview.files.contains { $0.kind == "file" } || preview.refused.isEmpty)
        #expect(!preview.summaryText.contains("PRIVATE") && !preview.manifestText.contains("PRIVATE"))
        guard case .refused(let reason)? = preview.refused.first?.decision else { return nil }
        return reason
    }

    @Test(arguments: [
        "../private.txt", "/etc/hosts.txt", "root/../../private.txt", "a//b.txt", "./allowed.txt",
        "\u{FF0E}\u{FF0E}/private.txt", "a\u{2215}..\u{2215}private.txt", "a\\..\\private.txt", "neighbor\u{0000}.txt",
    ])
    func traversalNamesAreRefusedBeforeAnyRead(_ name: String) throws {
        let layout = try Layout()
        #expect(throws: ExportSelectionError.self) {
            try ExportArtifact.file(name, in: layout.root, tier: .publicFixture, at: "files/out.txt")
        }
    }

    @Test(arguments: ["../out.txt", "/abs.txt", ".hidden/out.txt", "files/.out.txt", "summary.md", "MANIFEST.json", "files/out.png"])
    func unsafeOrReservedExportNamesAreRefused(_ exportName: String) throws {
        let layout = try Layout()
        #expect(throws: ExportSelectionError.self) {
            try ExportArtifact.file("allowed.txt", in: layout.root, tier: .publicFixture, at: exportName)
        }
    }

    @Test func aSymbolicLinkThatEscapesIsRefused() throws {
        let layout = try Layout()
        try FileManager.default.createSymbolicLink(
            at: layout.root.appending(path: "escape.txt"), withDestinationURL: layout.temporary.url.appending(path: "private.txt")
        )
        try FileManager.default.createSymbolicLink(
            at: layout.root.appending(path: "linked"), withDestinationURL: layout.temporary.url.appending(path: "neighbor")
        )
        let file = try reason(try .file("escape.txt", in: layout.root, tier: .publicFixture, at: "files/a.txt"))
        #expect(file?.contains("symbolic link") == true)
        let folder = try reason(try .file("linked/inside.txt", in: layout.root, tier: .publicFixture, at: "files/b.txt"))
        #expect(folder?.contains("symbolic link") == true)
    }

    @Test func aSymbolicLinkInsideTheRootIsRefusedToo() throws {
        let layout = try Layout()
        try FileManager.default.createSymbolicLink(
            at: layout.root.appending(path: "alias.txt"), withDestinationURL: layout.root.appending(path: "allowed.txt")
        )
        #expect(try reason(try .file("alias.txt", in: layout.root, tier: .publicFixture, at: "files/a.txt"))?.contains("symbolic link") == true)
    }

    @Test func hiddenFilesAndFoldersAreRefused() throws {
        let layout = try Layout()
        try layout.temporary.write("dotfile\n", to: "root/.secret.txt")
        try layout.temporary.write("in a dot folder\n", to: "root/.git/config.txt")
        let flagged = try layout.temporary.write("flagged hidden\n", to: "root/flagged.txt")
        #expect(chflags(flagged.path(percentEncoded: false), UInt32(UF_HIDDEN)) == 0)
        let flaggedFolder = try layout.temporary.folder("root/flagged-folder")
        try layout.temporary.write("inside a hidden folder\n", to: "root/flagged-folder/inside.txt")
        #expect(chflags(flaggedFolder.path(percentEncoded: false), UInt32(UF_HIDDEN)) == 0)

        for (source, index) in zip([".secret.txt", ".git/config.txt", "flagged.txt", "flagged-folder/inside.txt"], 0...) {
            let refusal = try reason(try .file(source, in: layout.root, tier: .publicFixture, at: "files/\(index).txt"))
            #expect(refusal?.contains("hidden") == true, "\(source)")
        }
    }

    @Test func aFolderIsNeverExportedWhole() throws {
        let layout = try Layout()
        _ = try layout.temporary.folder("root/looks-like-a-file.txt")
        try layout.temporary.write("inside\n", to: "root/looks-like-a-file.txt/inside.txt")
        let refusal = try reason(try .file("looks-like-a-file.txt", in: layout.root, tier: .publicFixture, at: "files/a.txt"))
        #expect(refusal?.contains("folder or a special file") == true)
    }

    @Test func aHardLinkedFileIsRefused() throws {
        let layout = try Layout()
        #expect(link(
            layout.temporary.url.appending(path: "private.txt").path(percentEncoded: false),
            layout.root.appending(path: "hard.txt").path(percentEncoded: false)
        ) == 0)
        #expect(try reason(try .file("hard.txt", in: layout.root, tier: .publicFixture, at: "files/a.txt"))?.contains("hard link") == true)
    }

    @Test func mediaAndBinariesAreRefused() throws {
        let layout = try Layout()
        for media in ["photo.png", "clip.mov", "voice.m4a", "archive.zip", "noextension"] {
            #expect(throws: ExportSelectionError.unsupportedFileType(StagedPathExtension(media))) {
                try ExportArtifact.file(media, in: layout.root, tier: .publicFixture, at: "files/out.txt")
            }
        }
        // A binary renamed to look like text is not UTF-8, so it is refused on reading.
        try layout.temporary.write(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF, 0xFE]), to: "root/photo.txt")
        #expect(try reason(try .file("photo.txt", in: layout.root, tier: .publicFixture, at: "files/a.txt"))?.contains("not UTF-8") == true)
        // A text file cannot be renamed to another type on export.
        #expect(throws: ExportSelectionError.extensionMismatch) {
            try ExportArtifact.file("allowed.txt", in: layout.root, tier: .publicFixture, at: "files/allowed.json")
        }
    }

    @Test func missingAndOversizedSourcesAreRefused() throws {
        let layout = try Layout()
        #expect(try reason(try .file("absent.txt", in: layout.root, tier: .publicFixture, at: "files/a.txt"))?.contains("does not exist") == true)
        let missingRoot = layout.temporary.url.appending(path: "no-such-root")
        #expect(try reason(try .file("allowed.txt", in: missingRoot, tier: .publicFixture, at: "files/a.txt"))?.contains("folder does not exist") == true)
        try layout.temporary.write(Data(repeating: 0x61, count: EvidenceExporter.maximumFileBytes + 1), to: "root/big.txt")
        #expect(try reason(try .file("big.txt", in: layout.root, tier: .publicFixture, at: "files/a.txt"))?.contains("larger than") == true)
    }

    @Test func exportNamesThatWouldCollideAreRefused() async throws {
        let layout = try Layout()
        let run = await DemoRunner.manual().run(try Showcase.script())
        let collisions: [[ExportArtifact]] = [
            [try .run(run, at: "runs/A.json"), try .run(run, at: "runs/a.json")],
            [try .run(run, at: "runs/x.json"), try .file("allowed.txt", in: layout.root, tier: .publicFixture, at: "runs/x.json/y.txt")],
            [try .file("allowed.txt", in: layout.root, tier: .publicFixture, at: "files/caf\u{E9}.txt"),
             try .file("allowed.txt", in: layout.root, tier: .publicFixture, at: "files/cafe\u{301}.txt")],
        ]
        for artifacts in collisions {
            #expect(throws: EvidenceExportError.self) {
                try exporter.preview(EvidenceExportRequest(title: "Collide", artifacts: artifacts, provenance: testProvenance))
            }
        }
    }

    @Test(arguments: ["../escape", ".hidden", "a/b", "", "."])
    func theExportFolderNameIsOneVisibleComponent(_ folderName: String) throws {
        let output = try TemporaryFolder()
        let preview = try exporter.preview(EvidenceExportRequest(title: "Name", artifacts: [], provenance: testProvenance))
        #expect(throws: EvidenceExportError.invalidFolderName) {
            try preview.write(into: output.url, folderName: folderName)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.url.path(percentEncoded: false)).isEmpty)
    }

    /// A file or folder swapped for a link after the walk checked it is refused when it is
    /// opened: the last component by `O_NOFOLLOW`, an earlier one by the descriptor's own path.
    @Test func aLinkSwappedInAfterTheCheckIsRefusedWhenOpened() throws {
        let layout = try Layout()
        let rootPath = try ConfinedFile.resolvedRoot(layout.root)
        let checked = try ConfinedFile.walk(try StagedPath("allowed.txt"), below: rootPath)
        #expect(try ConfinedFile.readChecked(atPath: checked, below: rootPath, maximumBytes: 64) == Data("allowed\n".utf8))

        // The checked file is replaced by a link to the private file beside the root.
        try FileManager.default.removeItem(atPath: checked)
        try FileManager.default.createSymbolicLink(
            atPath: checked, withDestinationPath: layout.temporary.url.appending(path: "private.txt").path(percentEncoded: false)
        )
        #expect(throws: ConfinementError.symbolicLink) {
            try ConfinedFile.readChecked(atPath: checked, below: rootPath, maximumBytes: 64)
        }

        // A checked folder is replaced by a link to a folder beside the root.
        _ = try layout.temporary.folder("root/notes")
        try layout.temporary.write("PRIVATE-FOLDER\n", to: "root/notes/inside.txt")
        let inside = try ConfinedFile.walk(try StagedPath("notes/inside.txt"), below: rootPath)
        try FileManager.default.removeItem(at: layout.root.appending(path: "notes"))
        try FileManager.default.createSymbolicLink(
            at: layout.root.appending(path: "notes"), withDestinationURL: layout.temporary.url.appending(path: "neighbor")
        )
        #expect(throws: ConfinementError.escapesRoot) {
            try ConfinedFile.readChecked(atPath: inside, below: rootPath, maximumBytes: 64)
        }
    }

    /// Before the folder is moved into place, the writer checks it holds exactly the previewed
    /// files and bytes. An extra file, a missing one, a changed byte, or a link fails the check.
    @Test func theWriterAcceptsOnlyAFolderThatMatchesThePreview() async throws {
        let run = await DemoRunner.manual().run(try Showcase.script())
        let preview = try exporter.preview(EvidenceExportRequest(
            title: "Verify", artifacts: [try .run(run, at: "runs/run.json")], provenance: testProvenance
        ))
        func folder(_ change: (URL) throws -> Void) throws -> Bool {
            let temporary = try TemporaryFolder()
            for file in preview.files { try temporary.write(file.data, to: file.path) }
            try change(temporary.url)
            do {
                try preview.verify(folder: temporary.url.path(percentEncoded: false))
                return true
            } catch {
                #expect(error == .verificationFailed)
                return false
            }
        }
        #expect(try folder { _ in })
        #expect(try !folder { try Data("extra\n".utf8).write(to: $0.appending(path: "runs/extra.json")) })
        #expect(try !folder { try Data("hidden\n".utf8).write(to: $0.appending(path: ".DS_Store")) })
        #expect(try !folder { try FileManager.default.createDirectory(at: $0.appending(path: "empty"), withIntermediateDirectories: false) })
        #expect(try !folder { try FileManager.default.removeItem(at: $0.appending(path: "summary.md")) })
        #expect(try !folder { try Data("changed\n".utf8).write(to: $0.appending(path: "runs/run.json")) })
        #expect(try !folder { url in
            try FileManager.default.removeItem(at: url.appending(path: "summary.md"))
            try FileManager.default.createSymbolicLink(at: url.appending(path: "summary.md"), withDestinationURL: url.appending(path: "manifest.json"))
        })
    }

    /// Nothing outside the chosen root ends up in the export, even when every refusal above is
    /// attempted in one request beside a valid file.
    @Test func onlyTheAllowlistReachesTheDestination() throws {
        let layout = try Layout()
        try FileManager.default.createSymbolicLink(
            at: layout.root.appending(path: "escape.txt"), withDestinationURL: layout.temporary.url.appending(path: "private.txt")
        )
        try layout.temporary.write("dotfile\n", to: "root/.secret.txt")
        let preview = try exporter.preview(EvidenceExportRequest(
            title: "Allowlist",
            artifacts: [
                try .file("allowed.txt", in: layout.root, tier: .publicFixture, at: "files/allowed.txt"),
                try .file("escape.txt", in: layout.root, tier: .publicFixture, at: "files/escape.txt"),
                try .file(".secret.txt", in: layout.root, tier: .publicFixture, at: "files/secret.txt"),
            ],
            provenance: testProvenance
        ))
        let output = try TemporaryFolder()
        let written = try preview.write(into: output.url, folderName: "export")
        #expect(output.files(below: written) == ["summary.md", "manifest.json", "files/allowed.txt"])
        #expect(preview.refused.map(\.path) == ["files/escape.txt", "files/secret.txt"])
        for file in output.files(below: written) {
            let text = try String(contentsOf: written.appending(path: file), encoding: .utf8)
            #expect(!text.contains("PRIVATE") && !text.contains("dotfile"), "\(file)")
            #expect(!text.contains(layout.temporary.url.path(percentEncoded: false)), "no source path in \(file)")
        }
    }
}

/// The lowercase extension `StagedPath` reports for a name.
private func StagedPathExtension(_ name: String) -> String {
    (try? StagedPath(name))?.pathExtension ?? ""
}
