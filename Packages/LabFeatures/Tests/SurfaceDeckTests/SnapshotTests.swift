import Foundation
import LabDomain
@testable import SurfaceDeck
import Testing

/// LAB-004: surfaces read an immutable, redacted-by-default snapshot. A stale or missing one shows
/// a safe placeholder, and nothing a surface reads can come from the store or a model.
@Suite struct SnapshotTests {
    static let written = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func aSnapshotIsRedactedByDefaultAndHoldsOnlyTheState() throws {
        let snapshot = SessionSnapshot(state: SessionState(isRunning: true, revision: 3), writtenAt: Self.written, detail: nil)
        #expect(snapshot.isRedacted)
        let object = try #require(try JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        #expect(Set(object.keys) == ["format", "formatVersion", "state", "writtenAt"])
        #expect(Set((object["state"] as? [String: Any])?.keys ?? [:].keys) == ["isRunning", "revision"])
        #expect(try snapshot.encoded().count < 200)
    }

    @Test func detailsAppearOnlyWhenIncluded() throws {
        let detail = SnapshotDetail(changedFrom: .control, changedAt: Self.written)
        let snapshot = SessionSnapshot(state: SessionState(isRunning: false, revision: 2), writtenAt: Self.written, detail: detail)
        #expect(!snapshot.isRedacted)
        #expect(SessionSnapshot.decode(try snapshot.encoded()) == snapshot)
        let object = try #require(try JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        #expect(Set((object["detail"] as? [String: Any])?.keys ?? [:].keys) == ["changedAt", "changedFrom"])
    }

    @Test func rewritingTheSameStateIsNotAChange() {
        let first = SessionSnapshot(state: SessionState(isRunning: true, revision: 1), writtenAt: Self.written, detail: nil)
        let later = SessionSnapshot(state: first.state, writtenAt: Self.written.addingTimeInterval(600), detail: nil)
        #expect(!later.differs(from: first))
        #expect(later.differs(from: nil))
        #expect(SessionSnapshot(state: .neverStarted, writtenAt: Self.written, detail: nil).differs(from: first))
        let shown = SessionSnapshot(state: first.state, writtenAt: Self.written, detail: SnapshotDetail(changedFrom: .app, changedAt: Self.written))
        #expect(shown.differs(from: first), "turning details on or off is a change a surface must show")
    }

    @Test(arguments: [
        #"{"format":"native-lab-session-snapshot","formatVersion":2,"state":{"isRunning":true,"revision":1},"writtenAt":1}"#,
        #"{"format":"something-else","formatVersion":1,"state":{"isRunning":true,"revision":1},"writtenAt":1}"#,
        #"{"format":"native-lab-session-snapshot","formatVersion":1,"state":{"isRunning":true},"writtenAt":1}"#,
        #"{"format":"native-lab-session-snapshot","formatVersion":1,"state":{"isRunning":false,"revision":0},"writtenAt":1}"#,
        #"{"format":"native-lab-session-snapshot","formatVersion":1,"state":{"isRunning":"yes","revision":1},"writtenAt":1}"#,
        #"{"format":"native-lab-session-snapshot","formatVersion":1}"#,
        "not json",
        "",
    ])
    func malformedOrForeignSnapshotsAreRefused(_ text: String) {
        #expect(SessionSnapshot.decode(Data(text.utf8)) == nil)
    }

    @Test func anOversizedSnapshotIsRefusedBeforeDecoding() throws {
        let padding = String(repeating: " ", count: SessionSnapshot.maximumBytes)
        let valid = try SessionSnapshot(state: .neverStarted, writtenAt: Self.written, detail: nil).encoded()
        #expect(SessionSnapshot.decode(valid) != nil)
        #expect(SessionSnapshot.decode(Data(padding.utf8) + valid) == nil)
    }

    @Test func theFileRoundTripsAndReportsMissingAndUnusableFiles() throws {
        let folder = try TemporaryFolder()
        let file = folder.snapshotFile
        #expect(file.read() == .missing)

        let snapshot = SessionSnapshot(state: SessionState(isRunning: true, revision: 5), writtenAt: Self.written, detail: nil)
        try file.write(snapshot)
        #expect(file.read() == .snapshot(snapshot))
        #expect(file.url.path().hasSuffix("Library/Application%20Support/Surface%20Deck/session-snapshot.json"))

        try Data("garbage".utf8).write(to: file.url)
        #expect(file.read() == .unreadable)

        try Data(count: SessionSnapshot.maximumBytes + 1).write(to: file.url)
        #expect(file.read() == .unreadable)

        // A link is refused even when it points at a good snapshot.
        let target = folder.url.appending(path: "elsewhere.json")
        try snapshot.encoded().write(to: target)
        try FileManager.default.removeItem(at: file.url)
        try FileManager.default.createSymbolicLink(at: file.url, withDestinationURL: target)
        #expect(file.read() == .unreadable)

        try FileManager.default.removeItem(at: file.url)
        try FileManager.default.createDirectory(at: file.url, withIntermediateDirectories: true)
        #expect(file.read() == .unreadable)
    }

    @Test func aBundleWithoutAnAppGroupHasNoSnapshotFile() {
        // The test runner declares no App Group, as a CoreLocal build declares none.
        #expect(SessionSnapshotFile.shared(for: .main) == nil)
    }
}

@Suite struct PresentationTests {
    static let written = Date(timeIntervalSince1970: 1_790_000_000)
    static let running = SessionSnapshot(state: SessionState(isRunning: true, revision: 4), writtenAt: written, detail: nil)

    @Test func aFreshSnapshotShowsItsStateWithDetailsHidden() {
        let shown = SurfacePresentation(reading: .snapshot(Self.running), confirmedAt: Self.written, now: Self.written.addingTimeInterval(60))
        #expect(shown.availability == .current)
        #expect(shown.isOn && shown.stateTitle == "Running")
        #expect(shown.seen == .revision(Revision(rawValue: 4)!))
        #expect(shown.isRedacted && shown.detailText == nil)
        #expect(shown.statusText == "Details hidden")
        #expect(shown.accessibilityLabel == "Demo session, Running.")
    }

    @Test func aSnapshotNotConfirmedWithinTheWindowSaysItMayBeOutOfDate() {
        let confirmed = Self.written.addingTimeInterval(30)
        let justBefore = SurfacePresentation(
            reading: .snapshot(Self.running), confirmedAt: confirmed, now: confirmed.addingTimeInterval(SurfacePresentation.staleAfter - 1)
        )
        #expect(justBefore.availability == .current)
        let stale = SurfacePresentation(
            reading: .snapshot(Self.running), confirmedAt: confirmed, now: confirmed.addingTimeInterval(SurfacePresentation.staleAfter)
        )
        #expect(stale.availability == .stale)
        #expect(stale.statusText == "May be out of date")
        #expect(stale.stateTitle == "Running", "a stale surface still says what it last knew, marked as such")
        #expect(stale.accessibilityLabel == "Demo session, Running, may be out of date.")
    }

    @Test(arguments: [SnapshotReading.missing, .unreadable])
    func aMissingOrUnusableSnapshotShowsASafePlaceholder(_ reading: SnapshotReading) {
        let shown = SurfacePresentation(reading: reading, confirmedAt: Self.written, now: Self.written)
        #expect(shown.availability == .unavailable)
        #expect(shown.state == nil && !shown.isOn)
        #expect(shown.seen == .unknown, "a toggle on the placeholder can only show the current state")
        #expect(shown.stateTitle == "Not available")
        #expect(shown.statusText == "Open Native Lab")
        #expect(shown.detailText == nil && shown.writtenAt == nil)
        #expect(SurfacePresentation.placeholder == shown)
    }

    @Test func detailsShowOnlyWhenTheSnapshotCarriesThem() {
        let detail = SnapshotDetail(changedFrom: .control, changedAt: Self.written)
        let snapshot = SessionSnapshot(state: SessionState(isRunning: false, revision: 2), writtenAt: Self.written, detail: detail)
        let shown = SurfacePresentation(reading: .snapshot(snapshot), confirmedAt: Self.written, now: Self.written)
        #expect(!shown.isRedacted)
        #expect(shown.detailText == "Changed from Control Center")
        #expect(!shown.accessibilityLabel.contains("Control Center"), "VoiceOver hears the detail only from the privacy-sensitive view")
        #expect(shown.seen == .revision(Revision(rawValue: 2)!))
    }

    @Test func aNeverStartedSessionOffersAToggleThatSawNoSession() {
        let snapshot = SessionSnapshot(state: .neverStarted, writtenAt: Self.written, detail: nil)
        let shown = SurfacePresentation(reading: .snapshot(snapshot), confirmedAt: Self.written, now: Self.written)
        #expect(shown.stateTitle == "Paused" && !shown.isOn)
        #expect(shown.seen == .neverStarted)
    }
}

/// LAB-004: a denied update budget leaves a correct stale indicator, and refresh is bounded.
@Suite struct TimelineTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let running = SessionSnapshot(state: SessionState(isRunning: true, revision: 4), writtenAt: now, detail: nil)

    @Test func aTimelineShowsTheSnapshotNowAndMarksItStaleIfTheNextRefreshNeverComes() {
        let timeline = SessionTimeline(reading: .snapshot(Self.running), now: Self.now)
        #expect(timeline.entries.map(\.date) == [Self.now, Self.now.addingTimeInterval(SurfacePresentation.staleAfter)])
        #expect(timeline.entries.map(\.presentation.availability) == [.current, .stale])
        #expect(timeline.entries.allSatisfy { $0.presentation.state == Self.running.state })
        // One refresh, at the moment the stale entry would show: granted, it never shows.
        #expect(timeline.refreshAfter == timeline.entries[1].date)
        #expect(SurfacePresentation.staleAfter == 3_600, "at most 24 refreshes a day besides the app's reloads on change")
    }

    @Test func aTimelineWithoutASnapshotIsThePlaceholderThroughout() {
        let timeline = SessionTimeline(reading: .missing, now: Self.now)
        #expect(timeline.entries.map(\.presentation.availability) == [.unavailable, .unavailable])
        #expect(timeline.entries.allSatisfy { !$0.presentation.isOn && $0.presentation.seen == .unknown })
    }
}

/// Widgets never read the database and never run inference: the module and the widget extension
/// import neither the store nor a model framework, and the module depends only on LabDomain.
@Suite struct SurfaceBoundaryTests {
    static let forbidden = ["import LabStore", "import SQLite3", "import FoundationModels", "import TypedIntelligence",
                            "import LabStaging", "SQLiteOperationStore", "SystemLanguageModel", "LanguageModelSession"]

    @Test(arguments: ["Packages/LabFeatures/Sources/SurfaceDeck", "Extensions/SurfaceWidgets"])
    func surfaceSourcesNeverReachTheStoreOrAModel(_ folder: String) throws {
        let files = try Repository.swiftFiles(in: folder)
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for needle in Self.forbidden {
                #expect(!text.contains(needle), "\(file.lastPathComponent) contains \(needle)")
            }
        }
    }

    @Test func theWidgetExtensionReadsOnlyTheSnapshotFile() throws {
        let text = try Repository.swiftFiles(in: "Extensions/SurfaceWidgets")
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        #expect(text.contains("SessionSnapshotFile.shared"))
        #expect(!text.contains("OperationService"), "the extension never composes a service")
        #expect(!text.contains("Timer."), "no polling timer")
    }
}
