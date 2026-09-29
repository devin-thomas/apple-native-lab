import Foundation
import LabCatalog
import LabSupport
import SwiftUI
import Testing
@testable import NativeLab

/// CORE-010: the key controls as VoiceOver and Voice Control receive them. Each test renders the
/// real shared view inside the running app, reads its accessibility tree, and where there is an
/// action, performs it through the accessibility press action rather than by calling code.
///
/// Display conditions are environment overrides in this process, standing in for Reduce Motion,
/// Reduce Transparency, Increase Contrast, Differentiate Without Color, and the largest text size.
/// They check that no condition removes a control or its result; they are not a pass with those
/// system settings on, and not a VoiceOver pass.
@MainActor
@Suite struct HostedAccessibilityTreeTests {
    let storeURL: URL

    init() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "HostedAccessibilityTreeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appending(path: LabStoreLocation.fileName)
    }

    private func startedLibrary() async -> LabLibrary {
        let url = storeURL
        let library = LabLibrary(locateStore: { url })
        await library.start()
        return library
    }

    @Test func everyStatusBadgeIsOneElementThatNamesItsKind() async throws {
        let hosted = HostedView(VStack {
            ForEach(ImplementationState.allCases, id: \.self) { StateBadge(state: $0) }
            ForEach(CapabilityReadiness.allCases, id: \.self) { ReadinessBadge(readiness: $0) }
        })
        defer { hosted.close() }
        let expected = ImplementationState.allCases.map { "State: \($0.title)" }
            + CapabilityReadiness.allCases.map { "Readiness: \($0.title)" }
        #expect(try await hosted.tree().labels == expected, "one element per badge; the symbol is not read separately")
    }

    @Test func anExperimentRowReadsInOrderWithItsState() async throws {
        let atlas = try #require(try ExperimentRegistry.bundled().experiment(id: "LAB-001"))
        let hosted = HostedView(VStack { ExperimentRow(experiment: atlas) })
        defer { hosted.close() }
        // The state comes from the registry, so this stays true as the experiment advances.
        #expect(try await hosted.tree().labels == ["Action Atlas, State: \(atlas.state.title), LAB-001, M1, System surfaces"])
    }

    @Test func resetDemoSaysWhatItDoesBeforeItAsks() async throws {
        let library = await startedLibrary()
        let hosted = HostedView(ResetDemoButton(isConfirming: .constant(false)).environment(library))
        defer { hosted.close() }
        let button = try #require(try await hosted.tree().buttons.first)
        #expect(button.label == "Reset Demo…")
        #expect(button.hint == "Asks before restoring every demo sample. Your own data is not changed.")
        #expect(button.isEnabled)
    }

    @Test(arguments: DisplayConditions.all)
    func aSampleArchivesAndRestoresThroughItsAccessibleButton(_ conditions: DisplayConditions) async throws {
        let library = await startedLibrary()
        let amber = try #require(library.collections.first?.items.first)
        let hosted = HostedView(DemoItemDetailView(itemID: amber.id).environment(library), conditions: conditions)
        defer { hosted.close() }

        let archive = try #require(try await hosted.tree().buttons.first { $0.label == "Archive Sample" }, "\(conditions)")
        #expect(archive.hint == "Hides the sample from normal view without deleting it. The receipt offers an undo.")
        #expect(try await hosted.press("Archive Sample"))
        #expect(try await eventually { library.item(id: amber.id)?.isArchived == true }, "\(conditions)")
        let archived = try await hosted.tree()
        #expect(archived.buttons.map(\.label).contains("Restore Sample"), "\(conditions)")
        #expect(archived.contains { $0.value == "Archived" }, "the record says Archived in words: \(conditions)")
        #expect(LabAnnouncement.outcome(of: library.latestReceipt, in: library)?.text
            == "Archived item “\(amber.title.value)”. Undo is available.")

        #expect(try await hosted.press("Restore Sample"))
        #expect(try await eventually { library.item(id: amber.id)?.isArchived == false }, "\(conditions)")
    }

    @Test(arguments: DisplayConditions.all)
    func aReceiptsUndoIsANamedButtonThatWorks(_ conditions: DisplayConditions) async throws {
        let library = await startedLibrary()
        let amber = try #require(library.collections.first?.items.first)
        let record = try #require(await library.setArchived(amber, true))
        let hosted = HostedView(ReceiptDetailView(record: record).environment(library), conditions: conditions)
        defer { hosted.close() }

        let tree = try await hosted.tree()
        #expect(tree.first(labeled: "Status: Committed") != nil, "\(conditions)")
        let undoLabel = "Undo: Restore Item “\(amber.title.value)”"
        let undo = try #require(tree.buttons.first { $0.label == undoLabel }, "\(conditions)\n\(tree.dump)")
        #expect(undo.hint == "Submits the undo as a new request with its own receipt.")
        // Reading order: status and summary, then the undo offer, then the request details.
        let headings = tree.filter { $0.role == "AXHeading" }.map(\.label)
        #expect(headings.prefix(3) == ["Archive Item", "Undo", "Request"])

        #expect(try await hosted.press(undoLabel))
        #expect(try await eventually { library.undone[record.id] != nil }, "\(conditions)")
        let undone = try await hosted.tree()
        #expect(!undone.buttons.contains { $0.label == undoLabel }, "a used undo offer is not offered again")
        #expect(undone.contains { "\($0.label)\($0.value)".contains("Undone: Restored item “\(amber.title.value)”.") },
                "\(conditions)\n\(undone.dump)")
    }

    @Test(arguments: [DisplayConditions.standard, DisplayConditions(reduceMotion: true)])
    func aCapabilityRowShowsItsGatesWithOrWithoutMotion(_ conditions: DisplayConditions) async throws {
        let report = try #require(CapabilityRegistry.live().excludedReports().first)
        let hosted = HostedView(Form { CapabilityRow(capability: report.capability, report: report) }.formStyle(.grouped),
                                conditions: conditions)
        defer { hosted.close() }

        let closed = try await hosted.tree()
        let row = try #require(closed.buttons.first)
        #expect(row.label.hasPrefix("\(report.capability.title), Readiness: \(report.readiness.title), "))
        #expect(row.value == "Gates hidden")
        #expect(row.hint == "Shows every gate and the alternate route.")

        #expect(try await hosted.press(row.label))
        let open = try await hosted.tree()
        #expect(open.buttons.first?.value == "Gates shown", "\(conditions)")
        // Each gate is one element that says its kind and state in words; SwiftUI exposes the
        // combined text as the element's value.
        for gate in report.gates {
            #expect(open.contains { ($0.label + $0.value).hasPrefix("\(gate.kind.title): \(gate.stateTitle)") },
                    "gate \(gate.kind.title) is shown in words: \(conditions)\n\(open.dump)")
        }
    }

    /// Polls a condition on the main actor until it holds or two seconds pass.
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}

extension DisplayConditions: CustomTestStringConvertible {
    var testDescription: String { description }
}
