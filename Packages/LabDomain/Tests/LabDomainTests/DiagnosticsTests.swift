import Foundation
import LabDomain
import Testing
#if canImport(OSLog)
import OSLog
#endif

/// CORE-006: metadata-only diagnostics, and a redacted export the person previews and places.
@Suite struct DiagnosticsTests {
    private static let fixedNow = Date(timeIntervalSince1970: 1_790_000_123.75)

    @Test func anEventIsOneMetadataLine() throws {
        let sink = CollectingDiagnosticSink()
        let log = DiagnosticsLog(sinks: [sink], now: { Self.fixedNow })
        let event = log.record(
            "import.stage", outcome: .rejected, subject: DiagnosticSubject("LAB-007"), category: .unsafePath,
            duration: .milliseconds(12) + .microseconds(900), counts: ["files": 3, "bytes": 2_048]
        )
        #expect(event.line == "phase=import.stage outcome=rejected category=unsafe-path subject=LAB-007 ms=12 bytes=2048 files=3")
        #expect(event.recordedAt == Date(timeIntervalSince1970: 1_790_000_123))
        #expect(event.sequence == 1)
        #expect(sink.events == [event])
        #expect(log.events == [event])
    }

    @Test func subjectsAreTicketOrExperimentIDsOnly() {
        for valid in ["LAB-007", "LAB-007-A", "CORE-006", "INT-001"] { #expect(DiagnosticSubject(valid) != nil, "\(valid)") }
        for invalid in ["", "lab-007", "LAB-7", "LAB-0071", "LAB-007-AB", Sentinels.fileName, Sentinels.token, "LAB-007 extra", "ÄB-007"] {
            #expect(DiagnosticSubject(invalid) == nil, "\(invalid)")
        }
    }

    @Test func errorsAreRecordedByCategoryNeverByText() {
        let log = DiagnosticsLog()
        let systemError = NSError(domain: NSCocoaErrorDomain, code: 260, userInfo: [
            NSFilePathErrorKey: Sentinels.path, NSLocalizedDescriptionKey: "The file “\(Sentinels.fileName)” couldn’t be opened.",
        ])
        let cases: [(any Error, DiagnosticCategory, DiagnosticOutcome)] = [
            (ImportRejection.unsafePath(file: 2, .parentReference), .unsafePath, .rejected),
            (ImportRejection.cancelled, .cancelled, .cancelled),
            (ImportRejection.storeUnavailable, .storeFailure, .failed),
            (GrantError.exceedsAdapterCeiling(.resetDemo), .unauthorized, .rejected),
            (OperationError.notFound(.item(ItemID())), .notFound, .rejected),
            (ValidationError.emptyTitle, .invalidInput, .rejected),
            (CancellationError(), .cancelled, .cancelled),
            (systemError, .other, .failed),
        ]
        for (error, category, outcome) in cases {
            let event = log.record("import.stage", failure: error)
            #expect(event.category == category && event.outcome == outcome, "\(category)")
            #expect(Sentinels.leaks(in: event.line).isEmpty)
        }
    }

    @Test func measureRecordsDurationAndOutcome() async throws {
        let log = DiagnosticsLog()
        let value = try await log.measure("work.succeeds", counts: ["items": 2]) { () async throws(ImportRejection) -> Int in 42 }
        #expect(value == 42)
        await #expect(throws: ImportRejection.corruptArchive) {
            try await log.measure("work.fails") { () async throws(ImportRejection) in throw .corruptArchive }
        }
        let events = log.events
        #expect(events.map(\.outcome) == [.succeeded, .rejected])
        #expect(events.map(\.category) == [nil, .unsafeArchive])
        #expect(events.allSatisfy { $0.durationMilliseconds != nil })
    }

    @Test func theLogKeepsOnlyRecentEventsAndCanBePurged() {
        let log = DiagnosticsLog(capacity: 3)
        for _ in 0..<5 { log.record("tick", outcome: .succeeded) }
        #expect(log.events.map(\.sequence) == [3, 4, 5])
        log.purge()
        #expect(log.events.isEmpty)
        #expect(log.record("tick", outcome: .succeeded).sequence == 6)
    }

    @Test func theExportIsExactlyItsPreview() throws {
        let log = DiagnosticsLog(now: { Self.fixedNow })
        log.record("import.stage", outcome: .succeeded, subject: DiagnosticSubject("LAB-007"), duration: .milliseconds(5), counts: ["files": 1])
        log.record("import.adopt", outcome: .rejected, subject: DiagnosticSubject("LAB-007"), category: .grantMissing)
        log.record("probe.read", outcome: .succeeded, subject: DiagnosticSubject("LAB-010"))

        let preview = log.exportPreview()
        #expect(preview.includedEventCount == 3 && preview.excludedEventCount == 0)
        #expect(preview.data == Data(preview.text.utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: preview.data) as? [String: Any])
        #expect(object["format"] as? String == "native-lab-diagnostics")
        #expect(object["formatVersion"] as? Int == 1)
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events.count == 3)
        // Times are rounded down to the minute, and sequence numbers are not exported.
        #expect(events[0]["recordedAt"] as? String == "2026-09-21T14:15:00Z")
        #expect(events[0]["sequence"] == nil)
        #expect(Set(events.flatMap(\.keys)).isSubset(of: [
            "recordedAt", "subject", "phase", "outcome", "category", "durationMilliseconds", "counts",
        ]))

        let folder = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsExport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appending(path: DiagnosticExportPreview.suggestedFileName)
        try preview.write(to: destination)
        #expect(try Data(contentsOf: destination) == preview.data)
        #expect(throws: (any Error).self) { try preview.write(to: destination) }
    }

    @Test func aSelectionNarrowsAndRedactsTheExport() throws {
        let log = DiagnosticsLog(now: { Self.fixedNow })
        log.record("import.stage", outcome: .succeeded, subject: DiagnosticSubject("LAB-007"), duration: .milliseconds(5), counts: ["files": 1])
        log.record("import.adopt", outcome: .rejected, subject: DiagnosticSubject("LAB-007"), category: .grantMissing)
        log.record("probe.read", outcome: .succeeded, subject: DiagnosticSubject("LAB-010"))
        log.record("grant.issue", outcome: .succeeded)

        let selection = DiagnosticExportSelection(
            subjects: [try #require(DiagnosticSubject("LAB-007"))], includeDurations: false, includeCounts: false
        )
        let preview = log.exportPreview(selection)
        #expect(preview.includedEventCount == 2 && preview.excludedEventCount == 2)
        #expect(!preview.text.contains("durationMilliseconds") && !preview.text.contains("counts"))
        #expect(!preview.text.contains("LAB-010") && !preview.text.contains("grant.issue"))
        let rejectedOnly = log.exportPreview(DiagnosticExportSelection(outcomes: [.rejected]))
        #expect(rejectedOnly.includedEventCount == 1 && rejectedOnly.text.contains("grant-missing"))
        #expect(DiagnosticExportPreview.redactionNotes.count >= 3)
    }

    #if os(macOS)
    /// Reads back what the system log actually stored for this process.
    @Test func theSystemLogReceivesOnlyTheMetadataLine() async throws {
        let subsystem = "NativeLabTests.\(UUID().uuidString)"
        let log = DiagnosticsLog(sinks: [OSLogDiagnosticSink(subsystem: subsystem)])
        let events = [
            log.record("import.stage", failure: ImportRejection.unsafePath(file: 1, .parentReference), subject: DiagnosticSubject("LAB-007")),
            log.record("import.adopt", failure: ImportRejection.grantMissing, counts: ["files": 2]),
        ]
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        var messages: [String] = []
        for _ in 0..<50 where messages.count < events.count {
            messages = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", subsystem))
                .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
            if messages.count < events.count { try await Task.sleep(for: .milliseconds(100)) }
        }
        #expect(messages == events.map(\.line))
        #expect(messages.allSatisfy { Sentinels.leaks(in: $0).isEmpty && !$0.contains("<private>") })
    }
    #endif
}
