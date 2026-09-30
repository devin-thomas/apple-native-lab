import Accessibility
import AccessSuperpower
import Foundation
import LabDomain
import LabStore
import LabSupport
import SwiftUI
import Testing
@testable import NativeLab

/// LAB-035-B criteria 2 and 3 with their evidence: in the sandboxed Mac app, each way of
/// finishing the task runs on its own fresh SQLite store with the practice set archived, acting
/// only through the accessibility tree or the keyboard, and each must end in the same restore,
/// the same receipt and announcement, and the same persisted state.
///
/// - The visible control: the selected sample's Restore Sample button, pressed through the
///   accessibility API, with the sample selected as a click on its row selects it.
/// - VoiceOver's structure: the bar that reads "the most", and its Restore action.
/// - The keyboard: Down five times and Return, delivered to the list by AppKit.
/// - The Audio Graph's data: the chart descriptor's highest value names the bar to act on.
/// - The fallback: the iPhone page without a descriptor, where the summary names the answer and
///   the list's Restore button finishes it.
///
/// The test attaches an `EvidenceRecord` of what it observed, with the toolchain read from this
/// app bundle. To keep it, run the test with a result bundle and export the attachment:
///
///     xcodebuild … -scheme LabMac-Core -only-testing:LabMacTests/AccessSuperpowerHostEvidenceTests \
///       -resultBundlePath <bundle> LAB_SOURCE_REVISION=<sha> test
///     xcrun xcresulttool export attachments --path <bundle> --output-path <folder>
@MainActor
@Suite struct AccessSuperpowerHostEvidenceTests {
    static let check = "Access as a Superpower in the Mac host: each way of finishing the task ends in the same restore, receipt, announcement, and persisted state"
    static let quartz = ItemID(rawValue: UUID(uuidString: "AF451890-CA80-4DE9-B18B-4007066C9177")!)

    enum Way: String, CaseIterable {
        case visibleButton = "visible-button"
        case voiceOverAction = "voiceover-action"
        case keyboard
        case audioGraphData = "audio-graph-data"
        case fallback

        var step: String {
            switch self {
            case .visibleButton: "visible-button: select Quartz point in the list as a click does, then press the detail column's Restore Sample button through the accessibility API"
            case .voiceOverAction: "voiceover-action: read the chart's bars, take the one whose value ends \"the most\", and perform its \"Restore Quartz point\" custom action"
            case .keyboard: "keyboard: give the list focus, then Down five times and Return, as AppKit delivers key presses; nothing is selected or pressed by the test"
            case .audioGraphData: "audio-graph-data: read the chart group's AXChartDescriptor, take the category of its highest value, and perform that bar's \"Restore Quartz point\" action"
            case .fallback: "fallback: the iPhone page with no chart descriptor; read the summary's answer, then press \"Restore Quartz point\" in the list"
            }
        }
    }

    struct Observed {
        var receipt: ActionReceipt?
        var announcement: String?
        /// The status badge and the result sentence as the accessibility tree reads them.
        var shownStatus = false
        var shownResult = false
        var items: [LabItem] = []
        var status: TaskStatus?
        var statusAfterUndo: TaskStatus?
        var notes: [String] = []
    }

    @Test func everyWayEndsInTheSameRestoreReceiptAndState() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "AccessSuperpowerHostEvidenceTests-\(UUID().uuidString)")
        let started = Date()
        var observed: [Way: Observed] = [:]
        for way in Way.allCases {
            observed[way] = try await Self.run(way, in: root.appending(path: way.rawValue))
        }

        // Every comparison is counted, and any difference is named in the record.
        var differences: [String] = []
        var comparisons = 0
        func compare(_ same: Bool, _ what: String) {
            comparisons += 1
            #expect(same, "\(what)")
            if !same { differences.append(what) }
        }
        let reference = try #require(observed[.visibleButton])
        let restore = DomainOperation.restoreItem(id: Self.quartz, expected: Revision(rawValue: 2)!)
        let announcement = "Restored item “Quartz point”. Undo is available. Task done: Mineral specimens had the most archived samples (3)."
        for way in Way.allCases {
            let seen = try #require(observed[way])
            for note in seen.notes { compare(false, "\(way.rawValue): \(note)") }
            compare(seen.receipt?.admitted.operation == restore, "\(way.rawValue) restores Quartz point at revision 2")
            compare(seen.receipt?.admitted.adapter == .appUI, "\(way.rawValue) commits as the app UI")
            compare(seen.receipt?.status == .committed && seen.receipt?.conflict == nil, "\(way.rawValue) commits")
            compare(seen.receipt?.changes == reference.receipt?.changes, "\(way.rawValue) changes")
            compare(seen.receipt?.summary == "Restored item “Quartz point”.", "\(way.rawValue) summary")
            compare(seen.receipt?.undo == .archiveItem(id: Self.quartz, expected: Revision(rawValue: 3)!), "\(way.rawValue) undo")
            compare(seen.announcement == announcement, "\(way.rawValue) announcement")
            compare(seen.status == .done, "\(way.rawValue) says the task is done")
            compare(seen.shownStatus, "\(way.rawValue) shows \"Task: Done\"")
            compare(seen.shownResult, "\(way.rawValue) shows the result sentence")
            compare(seen.items == reference.items && seen.items.count == 12, "\(way.rawValue) persisted state")
            compare(seen.statusAfterUndo == .toDo, "\(way.rawValue) undo makes the task to do again")
        }

        let seedBytes = try Data(contentsOf: try #require(Bundle.main.url(forResource: "seed", withExtension: "json")))
        let record = try EvidenceRecord(
            subject: "LAB-035",
            check: Self.check,
            date: started,
            provenance: .current,
            execution: .fixture,
            inputs: [
                "seed:app-bundle@sha256:\(ContentDigest.sha256(seedBytes).hex)",
                "practice:" + PracticeSet.standard.sampleIDs.map(\.description).joined(separator: ","),
                "restore:\(Self.quartz)",
            ],
            steps: [
                "xcodebuild -scheme LabMac-Core -only-testing:LabMacTests/AccessSuperpowerHostEvidenceTests test",
                "Each way on its own fresh SQLite store in the app container, seeded by the host's first run, then Set Up Practice through the task session: 6 archives, one receipt each",
            ] + Way.allCases.map(\.step) + [
                "After each way: read the receipt, the combined announcement, the task status, and every demo item from the store; then the receipt's undo, and the task status again",
            ],
            outcome: differences.isEmpty
                ? .passed(observed: "All \(comparisons) comparisons matched. Each of the 5 ways restored Quartz point from Mineral specimens at revision 2 as the app UI, with the receipt \"Restored item “Quartz point”.\" offering an archive at revision 3, and the announcement \"\(announcement)\" The task read Done after each, as the session's status and as \"Task: Done\" and the result sentence in the accessibility tree, and To Do after each undo. The 12 demo items were identical across the 5 stores. The chart descriptor's title, summary, categorical axis, and values 2, 3, and 1 named Mineral specimens as the highest, and the page without it still finished the task from its summary and list.")
                : .failed(observed: "\(differences.count) of \(comparisons) comparisons differed: " + differences.joined(separator: "; ") + "."),
            limitations: [
                "Fixture path: hosted tests in the sandboxed Mac app on the development Mac, on fresh stores seeded from the bundled demo seed. It supports implemented at most.",
                "Automated structure only. The accessibility API stands in for VoiceOver and Voice Control: nothing was spoken or heard, no Audio Graph was played, and no person used an assistive technology.",
                "The keyboard presses were delivered to the window by AppKit in the test process, not typed on a hardware keyboard, and Full Keyboard Access was off.",
                "The selection for the visible control was set as a click sets it; no pointer event was sent.",
                "The fallback page is the iPhone layout rendered on the Mac. No physical iPhone or iPad and no iOS simulator ran in this check.",
            ]
        )
        Attachment.record(try Self.json(record), named: "LAB-035-access-superpower-host-four-ways.json")
        #expect(record.result == .passed)
        #expect(record.provenance.xcodeBuild != "unknown" && record.provenance.sdkName.hasPrefix("macosx"))
        #expect(record.supportedState == .implemented)
    }

    /// Runs one way on a new store in `folder` and reports what it saw.
    static func run(_ way: Way, in folder: URL) async throws -> Observed {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        let window = MainWindowState()
        window.destination = .accessSuperpower
        let session = window.access
        session.setUpPractice(in: library)
        try await until { !session.isRunning }
        try #require(AccessTaskSession.tally(library).totalArchived == 6)

        var observed = Observed()
        // The Mac's two columns, or the iPhone page without a descriptor for the fallback, all
        // on the window's one session.
        let hosted: [AccessHostedView] = way == .fallback
            ? [AccessHostedView(
                NavigationStack { AccessSuperpowerPage(session: session) }.environment(library).environment(\.accessSonification, .unavailable)
            )]
            : [AccessHostedView(AccessSuperpowerListColumn(window: window, session: session).environment(library)),
               AccessHostedView(AccessSuperpowerDetailColumn(window: window, session: session).environment(library))]
        defer { hosted.forEach { $0.close() } }
        let list = hosted[0]
        let detail = hosted.count > 1 ? hosted[1] : hosted[0]
        func bar(named title: String, in elements: [AccessElement]) -> AccessElement? {
            elements.first { $0.label == title && $0.actions.contains("Restore Quartz point") }
        }

        switch way {
        case .visibleButton:
            session.selectedSampleID = quartz
            _ = try await detail.elements(until: { $0.contains { $0.role == "AXButton" && $0.label == "Restore Quartz point" } })
            if try await !detail.press("Restore Quartz point") { observed.notes.append("the Restore Sample button was not found") }
        case .voiceOverAction:
            let elements = try await detail.elements(until: { $0.contains { !$0.actions.isEmpty } })
            let most = elements.filter { !$0.actions.isEmpty && $0.value.hasSuffix(", the most") }
            if most.map(\.label) != ["Mineral specimens"] { observed.notes.append("the bars reading \"the most\" were \(most.map(\.label))") }
            if most.first?.perform(action: "Restore Quartz point") != true { observed.notes.append("the bar's action did not run") }
        case .keyboard:
            _ = try await list.elements(until: { $0.contains { $0.label.hasPrefix("Quartz point") } })
            if !list.pressKeysInList(Array(repeating: .down, count: 5)) { observed.notes.append("the list did not take focus") }
            try await until { session.selectedSampleID != nil }
            if session.selectedSampleID != quartz { observed.notes.append("five Down arrows selected \(String(describing: session.selectedSampleID))") }
            if !list.pressReturnInList() { observed.notes.append("Return was not delivered") }
        case .audioGraphData:
            let elements = try await detail.elements(until: { $0.contains { $0.chartDescriptor != nil } })
            let descriptor = try #require(elements.compactMap(\.chartDescriptor).first)
            let expected = ChartSemantics(tally: AccessTaskSession.tally(library))
            if descriptor.title != expected.title || descriptor.summary != expected.summary {
                observed.notes.append("the descriptor's title or summary differs from the chart's")
            }
            let categories = (descriptor.xAxis as? AXCategoricalDataAxisDescriptor)?.categoryOrder ?? []
            let points = descriptor.series.first?.dataPoints ?? []
            let values = points.map { $0.yValue?.value(forKey: "number") as? Double ?? -1 }
            if values != [2, 3, 1] || categories != ["Pigment swatches", "Mineral specimens", "Paper stock"] {
                observed.notes.append("the descriptor held \(categories) with \(values)")
            }
            let highest = values.indices.max { values[$0] < values[$1] }.map { points[$0].xValue.value(forKey: "category") as? String }
            guard let highest, let title = highest, let target = bar(named: title, in: elements) else {
                observed.notes.append("no bar matched the descriptor's highest value")
                break
            }
            if title != "Mineral specimens" { observed.notes.append("the highest value was \(title)") }
            if !target.perform(action: "Restore Quartz point") { observed.notes.append("the bar's action did not run") }
        case .fallback:
            let elements = try await list.elements(until: { $0.contains { $0.label == "Restore Quartz point" } })
            if elements.contains(where: { $0.chartDescriptor != nil }) { observed.notes.append("the page carried a descriptor") }
            if !elements.contains(where: { $0.spoken.contains("Mineral specimens has the most archived samples: 3 of 4.") }) {
                observed.notes.append("the summary did not name the answer")
            }
            if try await !list.press("Restore Quartz point") { observed.notes.append("the list's Restore button was not found") }
        }

        try await until { session.outcome != nil || !observed.notes.isEmpty }
        let result = "Task done: Mineral specimens had the most archived samples (3)."
        let status = try await list.elements(until: { $0.contains { $0.label == "Task: Done" } })
        observed.shownStatus = status.contains { $0.label == "Task: Done" }
        let shown = try await detail.elements(until: { $0.contains { $0.spoken.contains(result) } })
        observed.shownResult = shown.contains { $0.spoken.contains(result) }
        let record = library.latestReceipt
        observed.receipt = record?.receipt
        if let record { observed.announcement = AccessTaskSession.announcement(for: record, task: session.outcome?.task).text }
        observed.status = session.status(in: library)
        let store = try await SQLiteOperationStore(url: url)
        observed.items = try await store.items(in: nil).sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        if let record, await library.undo(record) != nil {
            observed.statusAfterUndo = session.status(in: library)
        }
        return observed
    }

    private static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func json(_ record: EvidenceRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
    }
}
