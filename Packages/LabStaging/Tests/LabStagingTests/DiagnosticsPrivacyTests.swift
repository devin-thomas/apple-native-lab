import Foundation
import LabDomain
import LabStaging
import Testing
#if canImport(OSLog)
import OSLog
#endif

/// CORE-006 acceptance: no default log contains raw prompts, filenames, tokens, or personal
/// content, through the real staging folder.
///
/// Private-looking material goes into every field a person controls: file names, text, a link's
/// host, path, query, and title, archive entry names, and JSON keys. The test then searches
/// everything diagnostic that resulted: the events, what the system log stored, the export, the
/// quarantine reason files, and the text of every error.
@Suite struct DiagnosticsPrivacyTests {
    @Test func privateMaterialNeverReachesDefaultOutput() async throws {
        let subsystem = "NativeLabTests.\(UUID().uuidString)"
        let sink = CollectingDiagnosticSink()
        let log = DiagnosticsLog(sinks: [sink, OSLogDiagnosticSink(subsystem: subsystem)])
        let staging = try StagingFixture(diagnostics: log)
        let area = staging.area
        var errors: [ImportRejection] = []
        func attempt<Value>(_ body: () async throws(ImportRejection) -> Value) async -> Value? {
            do { return try await body() } catch {
                errors.append(error)
                return nil
            }
        }

        // Accepted: text, a link, and files, each full of private material.
        let text = await attempt { () async throws(ImportRejection) in
            try await area.stageText("\(Sentinels.content)\n\(Sentinels.prompt)\nToken \(Sentinels.token)")
        }
        let url = try #require(URL(string: "https://\(Sentinels.host)/Avery/diary?token=\(Sentinels.token)"))
        let link = await attempt { () async throws(ImportRejection) in try await area.stageLink(url, title: Sentinels.content) }
        let files = await attempt { () async throws(ImportRejection) in
            try await area.stageFiles([.data(Data(Sentinels.content.utf8), name: Sentinels.fileName)])
        }

        // Refused: private names and content in hostile shapes.
        _ = await attempt { () async throws(ImportRejection) in
            try await area.stageFiles([.data(Data("x".utf8), name: "../\(Sentinels.fileName)")])
        }
        _ = await attempt { () async throws(ImportRejection) in
            try await area.stageFiles([.data(Data("{\"\(Sentinels.token)\":1,\"\(Sentinels.token)\":2}".utf8), name: "\(Sentinels.token).json")])
        }
        let archive = try staging.directory.file("shared.zip", ZipBuilder([
            ZipBuilder.Entry("Avery/\(Sentinels.fileName)", Data(count: 4 << 20)),
            ZipBuilder.Entry("../\(Sentinels.token).txt", Data(Sentinels.content.utf8)),
        ]).build())
        _ = await attempt { () async throws(ImportRejection) in try await area.stageArchive(at: archive) }
        let withCredentials = try #require(URL(string: "https://avery:\(Sentinels.token)@\(Sentinels.host)/"))
        _ = await attempt { () async throws(ImportRejection) in try await area.stageLink(withCredentials, title: nil) }

        // Tampered, so quarantined with a reason file.
        if let files {
            try Data(Sentinels.prompt.utf8).write(to: staging.pendingFolder(files.id).appending(path: "files/0"))
        }

        // The app: approval missing, then given; one tampered import, one attachment.
        let app = AppSide(diagnostics: log)
        let inbox = try await app.makeCollection()
        let adopter = ImportAdopter(service: app.service, inbox: area, ledger: app.ledger, diagnostics: log, subject: DiagnosticSubject("LAB-007"))
        for outcome in [text, link, files].compactMap({ $0 }) {
            _ = await attempt { () async throws(ImportRejection) in try await adopter.adopt(outcome.id, into: inbox) }
        }
        try app.ledger.issue(to: .shareExtension, for: [.createItem], on: .newItem(in: inbox))
        for outcome in [text, link, files].compactMap({ $0 }) {
            _ = await attempt { () async throws(ImportRejection) in try await adopter.adopt(outcome.id, into: inbox) }
        }
        #expect(try await app.items(in: inbox).count == 2, "the text and the link were adopted")
        #expect(errors.count >= 8)
        #expect(Set(log.events.compactMap(\.category)).isSuperset(of: [
            .unsafePath, .malformedData, .unsafeArchive, .invalidInput, .grantMissing, .tamperedStaging,
        ]))

        // Everything diagnostic, searched.
        var outputs = log.events.map(\.line) + sink.events.map(\.line) + [log.exportPreview().text]
        outputs += errors.flatMap { [$0.userMessage, $0.code, String(describing: $0), String(reflecting: $0), $0.localizedDescription] }
        let quarantine = staging.area.root.appending(path: "quarantine")
        for folder in staging.entries("quarantine") {
            outputs.append(try String(contentsOf: quarantine.appending(path: "\(folder)/reason.json"), encoding: .utf8))
        }
        #expect(staging.entries("quarantine").count == 1)
        #if os(macOS)
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        var logged: [String] = []
        for _ in 0..<50 {
            logged = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", subsystem))
                .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
            if logged.count >= log.events.filter({ $0.outcome == .rejected || $0.outcome == .failed }).count { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!logged.isEmpty, "the system log received the events")
        outputs += logged
        #endif
        for output in outputs {
            #expect(Sentinels.leaks(in: output).isEmpty, "leaked \(Sentinels.leaks(in: output)) in: \(output)")
        }
    }
}
