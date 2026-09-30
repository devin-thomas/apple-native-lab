import AccessSuperpower
import AppKit
import Foundation
import LabDomain
import LabStore
import SwiftUI
import Testing
@testable import NativeLab

/// LAB-035-B in the sandboxed Mac host: the whole task through the accessibility tree alone, the
/// keyboard alone, the chart without color, and the task's operations under cancellation, stale
/// state, a second press, and Reset Practice beside imported data. Each test uses a fresh SQLite
/// store in the app container's temporary folder, never the app's real store. They add to
/// `AccessSuperpowerAccessibilityTests` (LAB-035-A).
///
/// These are automated checks. They prove the structure and the paths a person would use, not
/// what VoiceOver speaks, that an Audio Graph plays, or how Voice Control or Full Keyboard Access
/// behave for a person (docs/ACCESSIBILITY_REVIEW.md).
@MainActor
@Suite struct AccessSuperpowerQualificationHostTests {
    let folder: URL

    static let quartz = ItemID(rawValue: UUID(uuidString: "AF451890-CA80-4DE9-B18B-4007066C9177")!)
    static let amber = ItemID(rawValue: UUID(uuidString: "DB666EF1-F642-43F1-B415-895B6ECFF693")!)

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "AccessSuperpowerQualificationHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func startedLibrary() async throws -> (LabLibrary, URL) {
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return (library, url)
    }

    private func practice(_ session: AccessTaskSession, in library: LabLibrary) async throws {
        session.setUpPractice(in: library)
        try await until { !session.isRunning }
        try #require(session.practiceCounts(in: library) == (toArchive: 0, toRestore: 6))
    }

    // MARK: Entering the experiment

    /// Opening the experiment, on the Mac's columns or on the iPhone page, changes nothing and
    /// grants nothing: the only receipt is the first run's seed, and nothing can be restored yet.
    @Test func openingTheExperimentChangesNothing() async throws {
        let (library, url) = try await startedLibrary()
        let receipts = library.receipts.count
        #expect(receipts == 1, "the first run's seed")
        let window = MainWindowState()
        window.destination = .accessSuperpower
        let list = AccessHostedView(AccessSuperpowerListColumn(window: window, session: window.access).environment(library))
        let detail = AccessHostedView(AccessSuperpowerDetailColumn(window: window, session: window.access).environment(library))
        let page = AccessHostedView(NavigationStack { AccessSuperpowerPage() }.environment(library))
        defer { list.close(); detail.close(); page.close() }

        let listed = try await list.elements(until: { $0.contains { $0.label == "Task: Nothing Archived" } })
        #expect(listed.contains { $0.label == "Task: Nothing Archived" }, "\(listed.dump)")
        let shown = try await page.elements(until: { $0.contains { $0.label == "Set Up Practice" } })
        #expect(shown.contains { $0.label == "Task: Nothing Archived" })
        #expect(!shown.contains { $0.role == "AXButton" && $0.label.hasPrefix("Restore ") })
        #expect(shown.first { $0.role == "AXButton" && $0.label == "Set Up Practice" }?.isEnabled == true)
        #expect(shown.first { $0.role == "AXButton" && $0.label == "Reset Practice" }?.isEnabled == false)
        _ = try await detail.elements()

        #expect(library.receipts.count == receipts, "no change was made by opening it")
        let store = try await SQLiteOperationStore(url: url)
        #expect(try await store.items(in: nil).allSatisfy { !$0.isArchived && $0.revision == .initial })
    }

    // MARK: Criterion 2: the whole task through the accessibility tree

    /// From nothing archived to Reset Practice, using only what VoiceOver and Voice Control use:
    /// buttons pressed by their labels, a bar chosen by the words it reads, and that bar's custom
    /// action. The receipt's Undo is pressed in the receipt view, as in the inspector.
    @Test func theWholeTaskFinishesThroughTheAccessibilityTreeAlone() async throws {
        let (library, _) = try await startedLibrary()
        let window = MainWindowState()
        window.destination = .accessSuperpower
        let session = window.access
        let list = AccessHostedView(AccessSuperpowerListColumn(window: window, session: session).environment(library))
        let detail = AccessHostedView(AccessSuperpowerDetailColumn(window: window, session: session).environment(library))
        defer { list.close(); detail.close() }

        // Set Up Practice, pressed as VoiceOver's VO-Space or Voice Control's "Tap" does.
        _ = try await detail.elements(until: { $0.contains { $0.label == "Set Up Practice" && $0.isEnabled } })
        #expect(try await detail.press("Set Up Practice"))
        try await until { !session.isRunning && AccessTaskSession.tally(library).totalArchived == 6 }
        let practiced = try await detail.elements(until: { $0.contains { $0.spoken.contains("Archived 6 practice samples.") } })
        #expect(practiced.contains { $0.spoken.contains("Archived 6 practice samples. Each has its own receipt.") }, "\(practiced.dump)")
        #expect(try await list.elements(until: { $0.contains { $0.label == "Task: To Do" } }).contains { $0.label == "Task: To Do" })

        // Find the answer by what each bar reads, then use that bar's first Restore action.
        let bars = practiced.filter { !$0.actions.isEmpty && $0.value.contains(" samples archived") }
        #expect(bars.count == 3)
        let most = bars.filter { $0.value.hasSuffix(", the most") }
        #expect(most.map(\.label) == ["Mineral specimens"])
        let bar = try #require(most.first)
        #expect(bar.actions.first == "Restore Banded agate slice")
        #expect(bar.perform(action: "Restore Banded agate slice"))

        let done = try await list.elements(until: { $0.contains { $0.label == "Task: Done" } })
        #expect(done.contains { $0.label == "Task: Done" }, "\(done.dump)")
        let finished = try await detail.elements(until: { $0.contains { $0.spoken.contains("Task done") } })
        #expect(finished.contains { $0.spoken.contains("Task done: Mineral specimens had the most archived samples (3).") })
        let record = try #require(library.latestReceipt)
        #expect(record.receipt.admitted.operation.kind == .restoreItem && record.receipt.admitted.adapter == .appUI)
        #expect(window.inspectedReceiptID == record.id)

        // The receipt's Undo, found by its label in the receipt view.
        let receipt = AccessHostedView(ReceiptDetailView(record: record).environment(library))
        defer { receipt.close() }
        let undo = try #require(try await receipt.elements().first { $0.role == "AXButton" && $0.label.hasPrefix("Undo: ") })
        #expect(try await receipt.press(undo.label))
        try await until { library.undone[record.id] != nil }
        #expect(try await list.elements(until: { $0.contains { $0.label == "Task: To Do" } }).contains { $0.label == "Task: To Do" })

        // Reset Practice, pressed by its label, restores the six practice samples.
        #expect(try await detail.press("Reset Practice"))
        try await until { !session.isRunning && AccessTaskSession.tally(library).totalArchived == 0 }
        #expect(session.message == "Restored 6 practice samples. Each has its own receipt.")
        #expect(try await list.elements(until: { $0.contains { $0.label == "Task: Nothing Archived" } })
            .contains { $0.label == "Task: Nothing Archived" })
    }

    // MARK: Criterion 1: the chart without color

    /// An archived square and an active one, rendered and read in grayscale. With the lab's tint,
    /// the archived square is filled and the active one is not. With the fill made the color of
    /// the background, the archived square's outline is still unbroken and the active one's is
    /// dashed, so the two differ even where no color or fill can be seen.
    @Test(arguments: [false, true])
    func archivedAndActiveSquaresDifferWithoutColor(increasedContrast: Bool) throws {
        let archived = try SquareImage(.archived, increasedContrast: increasedContrast)
        let active = try SquareImage(.active, increasedContrast: increasedContrast)
        #expect(archived.centerLuminance < 0.8, "filled: \(archived.centerLuminance)")
        #expect(active.centerLuminance > 0.95, "not filled: \(active.centerLuminance)")

        let hiddenFill = try SquareImage(.archived, increasedContrast: increasedContrast, tint: .white)
        #expect(hiddenFill.centerLuminance > 0.95, "the fill is invisible in this rendering")
        for edge in [hiddenFill.topEdge, hiddenFill.bottomEdge] {
            #expect(edge.inked > 0.95 && edge.gaps == 0, "the archived outline is unbroken: \(edge)")
        }
        for edge in [active.topEdge, active.bottomEdge] {
            #expect(edge.inked < 0.85 && edge.gaps >= 2, "the active outline is dashed: \(edge)")
        }
    }

    // MARK: Step 3: cancellation, stale state, a second press, and imported data

    /// Cancelling Set Up Practice between two commits keeps the archives already made, each with
    /// its receipt, and says so; Reset Practice then restores exactly those.
    @Test func cancellingSetUpPracticeKeepsWhatCommittedAndResetRestoresIt() async throws {
        let (library, _) = try await startedLibrary()
        let session = AccessTaskSession()
        session.setUpPractice(in: library)
        // Cancel once two practice receipts are listed after the seed's.
        for _ in 0..<100_000 where library.receipts.count < 3 {
            await Task.yield()
        }
        session.cancelPractice()
        try await until { !session.isRunning }
        let archived = AccessTaskSession.tally(library).totalArchived
        #expect((2..<6).contains(archived), "stopped between commits: \(archived)")
        #expect(session.message == "Stopped after \(archived) of 6. Archived \(archived) practice samples; each has its own receipt.")
        #expect(library.receipts.count == 1 + archived)
        #expect(library.receipts.dropLast().allSatisfy { $0.receipt.admitted.operation.kind == .archiveItem && $0.receipt.undo != nil })

        session.resetPractice(in: library)
        try await until { !session.isRunning }
        #expect(AccessTaskSession.tally(library).totalArchived == 0)
        #expect(session.message == "Restored \(archived) practice samples. Each has its own receipt.")
    }

    /// Another connection to the same store changes Quartz point after the chart was drawn. A
    /// restore from the stale chart is a conflict receipt: nothing changes and the task is not
    /// done. The conflict re-reads the store, so the next press restores at the new revision.
    @Test func aRestoreFromAStaleChartIsAConflictAndThenSucceedsFromTheNewOne() async throws {
        let (library, url) = try await startedLibrary()
        let session = AccessTaskSession()
        try await practice(session, in: library)
        let page = AccessHostedView(NavigationStack { AccessSuperpowerPage(session: session) }.environment(library))
        defer { page.close() }
        _ = try await page.elements(until: { $0.contains { $0.label == "Restore Quartz point" } })

        // Elsewhere: restore Quartz point and archive it again, revision 2 to 4.
        let ledger = GrantLedger()
        let other = OperationService(store: try await SQLiteOperationStore(url: url), policy: GrantAuthorizationPolicy(ledger: ledger))
        let actor = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
        _ = try await other.perform(OperationRequest(id: RequestID(), operation: .restoreItem(id: Self.quartz, expected: Revision(rawValue: 2)!), actor: actor))
        let archive = DomainOperation.archiveItem(id: Self.quartz, expected: Revision(rawValue: 3)!)
        let grant = try ledger.issue(for: archive, to: .appUI, lifetime: .seconds(30))
        _ = try await other.perform(OperationRequest(id: RequestID(), operation: archive, actor: actor))
        ledger.revoke(grant.id)
        #expect(library.item(id: Self.quartz)?.revision == Revision(rawValue: 2), "the chart still shows revision 2")

        #expect(try await page.press("Restore Quartz point"))
        try await until { library.latestReceipt?.receipt.admitted.operation.kind == .restoreItem && !session.isRunning }
        let conflict = try #require(library.latestReceipt)
        #expect(conflict.receipt.conflict != nil && conflict.receipt.changes.isEmpty)
        #expect(conflict.receipt.admitted.operation == .restoreItem(id: Self.quartz, expected: Revision(rawValue: 2)!))
        #expect(session.message == conflict.receipt.summary)
        #expect(session.outcome == nil)
        #expect(session.status(in: library) == .toDo)
        let shown = try await page.elements(until: { $0.contains { $0.spoken.contains(conflict.receipt.summary) } })
        #expect(shown.contains { $0.spoken.contains(conflict.receipt.summary) }, "the refusal is on screen\n\(shown.dump)")
        #expect(!shown.contains { $0.label == "Task: Done" })

        #expect(library.item(id: Self.quartz)?.revision == Revision(rawValue: 4), "the conflict re-read the store")
        _ = try await page.elements(until: { $0.contains { $0.role == "AXButton" && $0.label == "Restore Quartz point" && $0.isEnabled } })
        #expect(try await page.press("Restore Quartz point"))
        try await until { session.outcome != nil }
        #expect(library.latestReceipt?.receipt.admitted.operation == .restoreItem(id: Self.quartz, expected: Revision(rawValue: 4)!))
        #expect(session.status(in: library) == .done)
    }

    /// A second press while the restore runs is ignored, so one decision commits once.
    @Test func aSecondPressWhileTheRestoreRunsCommitsOnce() async throws {
        let (library, _) = try await startedLibrary()
        let session = AccessTaskSession()
        try await practice(session, in: library)
        let receipts = library.receipts.count
        let first = Task { await session.restore(Self.quartz, in: library) != nil }
        let second = Task { await session.restore(Self.quartz, in: library) != nil }
        let committed = [await first.value, await second.value]
        #expect(committed == [true, false], "the second press found the first still running")
        #expect(library.receipts.count == receipts + 1)
        #expect(library.item(id: Self.quartz)?.revision == Revision(rawValue: 3), "restored once")
        #expect(session.status(in: library) == .done)
    }

    /// Reset Practice beside the person's own data: a collection made in the app, an item imported
    /// by a second connection to the same store file as the share extension writes it, that item
    /// archived by the person, and a demo sample the person archived that is not a practice
    /// sample. None of it is counted by the task or changed by Reset Practice.
    @Test func resetPracticeLeavesImportedAndOwnDataUntouched() async throws {
        let (library, url) = try await startedLibrary()
        let notes = CollectionDraft(title: try EntityTitle("Field notes"))
        _ = try await library.submit(.createCollection(draft: notes), requestID: RequestID(), authority: .userAction, names: [:])

        let ledger = GrantLedger()
        let extensionService = OperationService(store: try await SQLiteOperationStore(url: url), policy: GrantAuthorizationPolicy(ledger: ledger))
        let inbox = InMemoryStagingInbox()
        let staged = await inbox.stage(try StagingRecord.text(utf8: Array("Harbor walk\nBring the blue notebook.".utf8)))
        try ledger.issue(to: .shareExtension, for: [.createItem], on: ImportAdopter.grantTarget(into: notes.id))
        let imported = try await ImportAdopter(service: extensionService, inbox: inbox, ledger: ledger).adopt(staged.id, into: notes.id)
        #expect(imported.receipt.admitted.adapter == .shareExtension)
        guard case .createItem(let draft) = imported.receipt.admitted.operation else {
            Issue.record("the import creates an item")
            return
        }
        _ = try await library.submit(.archiveItem(id: draft.id, expected: .initial), requestID: RequestID(), authority: .userAction, names: [:])
        let amber = try #require(library.item(id: Self.amber))
        #expect(await library.setArchived(amber, true)?.receipt.conflict == nil)

        let reader = try await SQLiteOperationStore(url: url)
        func userState() async throws -> ([LabCollection], [LabItem]) {
            (
                try await reader.collections().filter { $0.namespace == .user }.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString },
                try await reader.items(in: nil).filter { $0.namespace == .user }.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
            )
        }
        let before = try await userState()
        #expect(before.0.count == 1 && before.1.count == 1 && before.1.first?.isArchived == true)

        let session = AccessTaskSession()
        try await practice(session, in: library)
        #expect(AccessTaskSession.tally(library).collections.count == 3, "only the demo collections are counted")
        #expect(await session.restore(Self.quartz, in: library)?.receipt.conflict == nil)
        #expect(session.status(in: library) == .done)
        session.resetPractice(in: library)
        try await until { !session.isRunning }
        #expect(session.message == "Restored 5 practice samples. Each has its own receipt.")

        let after = try await userState()
        #expect(after.0 == before.0)
        #expect(after.1 == before.1)
        #expect(try await reader.receipt(for: imported.receipt.requestID) == imported.receipt)
        let tally = AccessTaskSession.tally(library)
        #expect(tally.totalArchived == 1 && tally.sample(Self.amber)?.sample.isArchived == true, "Amber swatch is not a practice sample")
    }

    // MARK: Helpers

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(condition())
    }
}

/// One `SampleSquare` rendered by SwiftUI at 2x on a white background in the light appearance,
/// read back as luminance (0 is black, 1 is white).
@MainActor
struct SquareImage {
    struct Edge: CustomStringConvertible {
        /// The share of the edge's straight run that is drawn.
        let inked: Double
        /// How many times the drawn run breaks.
        let gaps: Int

        var description: String { "inked \(inked), gaps \(gaps)" }
    }

    static let side = 32
    static let margin = 8
    static let scale = 2

    private let width: Int
    private let luminance: [Double]

    init(_ mark: SampleSquare.Mark, increasedContrast: Bool, tint: Color? = nil) throws {
        let square = SampleSquare(mark: mark)
            .frame(width: CGFloat(Self.side), height: CGFloat(Self.side))
            .padding(CGFloat(Self.margin))
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\._colorSchemeContrast, increasedContrast ? .increased : .standard)
        let renderer = ImageRenderer(content: square.tint(tint))
        renderer.scale = CGFloat(Self.scale)
        let image = try #require(renderer.cgImage)
        let (width, height) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        self.width = width
        // Split into typed steps: Swift 6.2's type checker times out on the one-line sum.
        luminance = stride(from: 0, to: bytes.count, by: 4).map { (index: Int) -> Double in
            let red: Double = 0.2126 * Double(bytes[index])
            let green: Double = 0.7152 * Double(bytes[index + 1])
            let blue: Double = 0.0722 * Double(bytes[index + 2])
            return (red + green + blue) / 255
        }
    }

    private func value(_ x: Int, _ y: Int) -> Double { luminance[y * width + x] }

    private var inset: Int { Self.margin * Self.scale }
    private var span: Int { Self.side * Self.scale }

    var centerLuminance: Double { value(inset + span / 2, inset + span / 2) }

    /// The outline's straight run along one edge, away from the rounded corners, read on the
    /// middle row of the outline's width.
    private func edge(row: Int) -> Edge {
        let corner = 6 * Self.scale
        let run = (inset + corner)..<(inset + span - corner)
        let drawn = run.map { value($0, row) < 0.85 }
        let gaps = zip(drawn, drawn.dropFirst()).filter { $0.0 && !$0.1 }.count
        return Edge(inked: Double(drawn.filter(\.self).count) / Double(drawn.count), gaps: gaps)
    }

    var topEdge: Edge { edge(row: inset + 1) }
    var bottomEdge: Edge { edge(row: inset + span - 2) }
}
