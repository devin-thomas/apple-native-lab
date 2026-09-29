import Foundation
import LabDomain
import Testing

/// CORE-006 acceptance: no default log contains raw prompts, filenames, tokens, or personal content.
///
/// The test drives staging, rejection, grants, and adoption with private-looking material in
/// every field a person controls, then searches everything diagnostics produced: each event's
/// line, what a sink received, the export, and the text of every error thrown on the way.
@Suite struct DiagnosticsPrivacyTests {
    @Test func privateMaterialNeverReachesDiagnostics() async throws {
        let sink = CollectingDiagnosticSink()
        let log = DiagnosticsLog(sinks: [sink])
        let lab = GrantedLab(diagnostics: log)
        let inbox = try await lab.makeCollection()
        var errors: [any Error] = []

        // Accepted content carrying every sentinel.
        let text = "\(Sentinels.content)\n\(Sentinels.prompt)\nToken: \(Sentinels.token)\nSaved at \(Sentinels.path)"
        let url = try #require(URL(string: "https://\(Sentinels.host)/reset?token=\(Sentinels.token)"))
        let textID = try await lab.stageText(text)
        let linkID = await lab.inbox.stage(try StagingRecord(payload: .link(url, title: Sentinels.pageTitle))).id
        let files = await lab.inbox.stage(try StagingRecord(payload: .files([
            StagedFile(path: try StagedPath("\(Sentinels.fileName)"), byteCount: 4, sha256: .sha256(Data("scan".utf8))),
        ]))).id

        // Refused content carrying them too.
        for hostile in ["../\(Sentinels.fileName)", "\(Sentinels.token)\u{202E}fdp.exe", "/Users/avery.example/\(Sentinels.fileName)"] {
            do { _ = try StagedPath(hostile) } catch { errors.append(ImportRejection.unsafePath(file: 1, error)) }
        }
        let secretJSON = Data("{\"\(Sentinels.token)\":1,\"\(Sentinels.token)\":2}".utf8)
        do { try StrictJSON.validate(secretJSON, maximumDepth: 16, maximumBytes: 1_000) } catch { errors.append(error) }
        await lab.inbox.storeUnchecked(Data("{\"\(Sentinels.prompt)\":\"\(Sentinels.content)\"}".utf8), as: StagingID(rawValue: UUID()))

        // Adoption without and then with approval, and a refused attachment.
        for id in [textID, linkID, files] {
            do { _ = try await lab.adopter.adopt(id, into: inbox.id) } catch { errors.append(error) }
        }
        try lab.approve(into: inbox.id)
        for id in [textID, linkID, files] + (await lab.inbox.waitingIDs) {
            do { _ = try await lab.adopter.adopt(id, into: inbox.id) } catch { errors.append(error) }
        }
        do { _ = try lab.ledger.issue(to: .shareExtension, for: [.resetDemo], on: .demo) } catch { errors.append(error) }

        #expect(errors.count >= 8)
        #expect(log.events.count >= 8)
        #expect(Set(log.events.compactMap(\.category)).isSuperset(of: [.grantMissing, .unsupported, .malformedData]))

        var outputs = log.events.map(\.line) + sink.events.map(\.line)
        outputs.append(log.exportPreview().text)
        outputs += errors.flatMap { error in
            [String(describing: error), String(reflecting: error), error.localizedDescription]
                + ((error as? ImportRejection).map { [$0.userMessage, $0.code] } ?? [])
        }
        for output in outputs {
            #expect(Sentinels.leaks(in: output).isEmpty, "leaked: \(Sentinels.leaks(in: output))")
        }
    }
}
