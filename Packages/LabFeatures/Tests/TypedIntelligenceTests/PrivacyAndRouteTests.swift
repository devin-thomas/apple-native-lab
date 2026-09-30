import CryptoKit
import Foundation
import LabDomain
import Testing
@testable import TypedIntelligence

/// Diagnostics hold no note, prompt, or output; there is no network or cloud route; the fixtures
/// are the files the evidence names.
@Suite struct PrivacyAndRouteTests {
    /// Runs every path, including hostile output and a commit, then searches every diagnostic line
    /// and the full export for any text from the notes, the samples, or the drafts.
    @Test func diagnosticsNeverHoldTheNotePromptOrOutput() async throws {
        let lab = try await Lab.seeded(timeLimit: .milliseconds(200))
        let candidates = try await lab.candidates()
        for fixture in IntelligenceFixture.allCases {
            let note = try Repository.note(fixture)
            let parsed = try await lab.flow.draft(note, with: SampleParser(), candidates: candidates).get()
            if parsed.isApprovable { _ = try await lab.flow.commit(try parsed.approve()) }
            _ = await lab.flow.draft(note, with: ScriptedExtractor(returning: HostileModelTests.hostileDrafts[0]), candidates: candidates)
            _ = await lab.flow.draft(note, with: ScriptedExtractor { _ throws(ExtractionFailure) -> ExtractionDraft in
                await uncancellableWait(1)
                throw .other
            }, candidates: candidates)
            _ = await lab.flow.revise(ProposalFields(target: .title("Kraft card"), newTitle: "Kraft card", addedNote: "tacky secret"),
                                      source: .manualEditor, note: note, candidates: candidates)
        }
        let events = lab.events.events
        #expect(events.count >= 8)
        let text = events.map(\.line).joined(separator: "\n") + "\n" + (try DiagnosticsLog.exportText(events))
        var forbidden = ["vellum", "tacky", "cobalt", "Cobalt", "Kraft", "kraft", "GRANT-", "OVERRIDE", "secret", "bleeds", "archive-collection", "prompt"]
        forbidden += candidates.map(\.title)
        for word in forbidden {
            #expect(!text.contains(word), "\(word) reached diagnostics")
        }
        #expect(events.allSatisfy { $0.subject?.rawValue == "LAB-010" })
    }

    /// No network or cloud route exists in the experiment's code: no Private Cloud Compute model,
    /// no URL loading, no sockets. Searches the package target and the host views.
    @Test func thereIsNoNetworkOrCloudRoute() throws {
        let forbidden = [
            "PrivateCloudCompute", "URLSession", "URLRequest", "NWConnection", "NWBrowser", "import Network",
            "CloudKit", "CKContainer", "WebSocket", "http://", "https://", "SFSafari", "WKWebView",
        ]
        let folders = [
            Repository.root.appending(path: "Packages/LabFeatures/Sources/TypedIntelligence"),
            Repository.root.appending(path: "Apps/Shared/Intelligence"),
        ]
        var searched = 0
        for folder in folders {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
            #expect(!files.isEmpty, "\(folder.lastPathComponent) has sources")
            for file in files {
                let source = try String(contentsOf: file, encoding: .utf8)
                searched += 1
                for symbol in forbidden {
                    #expect(!source.contains(symbol), "\(file.lastPathComponent) mentions \(symbol)")
                }
            }
        }
        #expect(searched >= 10)
        // The one model the extractor names is the system's on-device model.
        let extractor = try String(contentsOf: folders[0].appending(path: "OnDeviceModelExtractor.swift"), encoding: .utf8)
        #expect(extractor.contains("LanguageModelSession(\n            model: .default,"))
        #expect(extractor.components(separatedBy: "LanguageModelSession(").count == 2, "one session, built in one place")
    }

    @Test func theFixturesAreTheFilesTheEvidenceNames() throws {
        let expected: [IntelligenceFixture: String] = [
            .ambiguousNote: "86ecae7623d604f22613834ded5c021958c4b2a9b2cb064a54d158c9aa58d8ae",
            .injectedNote: "3c698a5d914355d243288491422b45bdaf9d8bf3b5ec8b2229a2c70554070019",
        ]
        for fixture in IntelligenceFixture.allCases {
            let data = try Data(contentsOf: Repository.fixtureURL(fixture))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(digest == expected[fixture], "\(fixture.fileName) changed; update the evidence that cites it")
            let note = try Repository.note(fixture)
            #expect(note.origin == .fixture(fixture))
        }
    }

    @Test func notesAreBoundedBeforeAnyExtractorSeesThem() {
        #expect(throws: SourceNoteError.empty) { try SourceNote(" \n ") }
        #expect(throws: SourceNoteError.tooLong(limit: ProposalLimits.sourceNote)) {
            try SourceNote(String(repeating: "a", count: ProposalLimits.sourceNote + 1))
        }
        #expect(throws: SourceNoteError.controlCharacter) { try SourceNote("a\u{0}b") }
        #expect(throws: SourceNoteError.fixtureUnreadable) { try IntelligenceFixture.ambiguousNote.load(from: .main) }
    }

    @Test func theHostileFixtureIsDataToTheParser() throws {
        let note = try Repository.note(.injectedNote)
        #expect(note.text.contains("SYSTEM OVERRIDE"))
        #expect(note.text.contains("GRANT-00000000-0000-0000-0000-000000000000"))
    }
}

extension DiagnosticsLog {
    /// Every field an export of these events can contain, as JSON text.
    static func exportText(_ events: [DiagnosticEvent]) throws -> String {
        String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
    }
}
