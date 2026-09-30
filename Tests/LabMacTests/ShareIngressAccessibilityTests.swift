import AppKit
import Foundation
import LabDomain
import ShareIngress
import SwiftUI
import Testing
@testable import NativeLab

/// LAB-007-B step 5: the share inbox's views through the accessibility API, rendered inside the
/// running Mac app and pressed through the accessibility press action. It covers the intake
/// controls with Choose Files on and off, the rows, an intake's result, and the review screen from
/// New Collection… to Add.
///
/// This is not a VoiceOver, Voice Control, or Full Keyboard Access pass; see
/// docs/ACCESSIBILITY_REVIEW.md for what that means.
@MainActor
@Suite struct ShareIngressAccessibilityTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ShareIngressAccessibilityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func started(canChooseFiles: Bool = true) async throws -> (LabLibrary, ShareInboxModel) {
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let hostRoot = folder.appending(path: "Share Inbox")
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let inbox = ShareInboxModel(locateHost: { hostRoot }, canChooseFiles: canChooseFiles)
        await inbox.start()
        try #require(inbox.phase == .ready)
        return (library, inbox)
    }

    private func tree(of hosted: HostedView, until condition: ([AccessibilityNode]) -> Bool) async throws -> [AccessibilityNode] {
        var nodes: [AccessibilityNode] = []
        for _ in 0..<20 {
            nodes = try await hosted.tree()
            if condition(nodes) { return nodes }
        }
        Issue.record("the view never reached the expected state\n\(nodes.dump)")
        return nodes
    }

    /// Paste and Choose Files are named buttons. With the entitlement, Choose Files is enabled and
    /// says what it does; without it, it stays in place, disabled, and its hint gives the way round.
    @Test(arguments: [true, false])
    func theIntakeControlsNameTheirActionsWithAndWithoutTheFilePicker(canChooseFiles: Bool) async throws {
        let (_, inbox) = try await started(canChooseFiles: canChooseFiles)
        let hosted = HostedView(HStack { InboxIntakeControls(model: inbox, isChoosingFiles: .constant(false)) })
        defer { hosted.close() }
        let nodes = try await tree(of: hosted) { $0.buttons.contains { $0.label == "Choose Files…" } }
        let choose = try #require(nodes.buttons.first(labeled: "Choose Files…"), "\(nodes.dump)")
        #expect(choose.isEnabled == canChooseFiles)
        #expect(choose.hint == (canChooseFiles
            ? "Adds files you choose to the inbox for review"
            : "Unavailable in this build. Paste a copied file or drag it here instead."))
        #expect(nodes.buttons.contains { $0.label.localizedCaseInsensitiveContains("Paste") }, "\(nodes.dump)")
    }

    /// Each waiting import is one element that reads its content, kind, and origin with commas, and
    /// a file says it cannot be added yet.
    @Test func eachWaitingImportReadsAsOneElement() async throws {
        let (_, inbox) = try await started()
        let file = folder.appending(path: "gull-count.txt")
        try ShareIngressFixtures.intake("gull-count.txt").write(to: file)
        inbox.paste([NSItemProvider(object: "Harbor walk\nBring the blue notebook." as NSString)])
        await inbox.waitForIntake()
        try await Task.sleep(for: .milliseconds(1_100))
        inbox.importFiles([file])
        await inbox.waitForIntake()
        let entries = inbox.snapshot.entries
        try #require(entries.count == 2)

        let hosted = HostedView(VStack { ForEach(entries) { InboxEntryRow(entry: $0) } })
        defer { hosted.close() }
        let nodes = try await tree(of: hosted) { $0.labels.count >= 2 }
        let spoken = nodes.labels
        #expect(spoken == entries.map(\.spokenDescription), "\(nodes.dump)")
        #expect(spoken.first?.hasPrefix("Harbor walk, Text, Paste, ") == true)
        #expect(spoken.last?.hasPrefix("gull-count.txt, File, File picker, ") == true)
        #expect(spoken.last?.hasSuffix(", Can't be added in this version") == true)
        #expect(spoken.allSatisfy { !$0.contains("·") })
    }

    /// An intake's result reads as one element: the summary, then each refusal by position.
    @Test func anIntakesResultReadsItsSummaryAndEachRefusal() async throws {
        let (_, inbox) = try await started()
        inbox.paste([
            NSItemProvider(object: URL(string: "https://user:secret@example.org/")! as NSURL),
            NSItemProvider(object: "Harbor walk" as NSString),
        ])
        await inbox.waitForIntake()
        let hosted = HostedView(InboxIntakeStatus(model: inbox))
        defer { hosted.close() }
        let nodes = try await tree(of: hosted) { $0.contains { !$0.value.isEmpty } }
        // One element holds the summary and the refusal, so they are read together.
        let read = nodes.map { $0.label + $0.value }.filter { $0.contains("was refused") }
        #expect(read.count == 1, "\(nodes.dump)")
        #expect(read.first?.hasPrefix("1 item is waiting for review, 1 was refused.") == true)
        #expect(read.first?.contains("Item 1: The shared link contains a user name or password, so it wasn’t imported.") == true)
        #expect(!nodes.contains { ($0.label + $0.value).contains("secret") })
    }

    /// The review screen, pressed through accessibility: Add stays disabled until the person has a
    /// collection of their own, then adds the import and hands over its receipt.
    @Test func theReviewScreenCompletesThroughAccessibilityPresses() async throws {
        let (library, inbox) = try await started()
        inbox.paste([NSItemProvider(object: "Harbor walk\nBring the blue notebook." as NSString)])
        await inbox.waitForIntake()
        let entry = try #require(inbox.snapshot.entries.first)
        let opened = OpenedReceipts()
        let hosted = HostedView(
            InboxEntryDetail(entry: entry, model: inbox) { opened.records.append($0) }.environment(library),
            size: CGSize(width: 560, height: 1_400)
        )
        defer { hosted.close() }

        let start = try await tree(of: hosted) { $0.buttons.contains { $0.label == "Add to Collection" } }
        #expect(try #require(start.buttons.first(labeled: "Add to Collection")).isEnabled == false, "no collection of the person's own yet")
        #expect(start.buttons.contains { $0.label == "New Collection…" && $0.isEnabled })
        #expect(start.buttons.contains { $0.label == "Remove from Inbox" && $0.isEnabled })
        let values = start.map(\.value)
        #expect(values.contains("Came through") && values.contains("Paste"), "the origin is read\n\(start.dump)")
        #expect(values.contains("Adds as") && values.contains("App UI"))

        // The collection is created as the alert's Create button does, then Add is pressed.
        #expect(await inbox.createCollection(titled: "Field notes", in: library))
        let ready = try await tree(of: hosted) { $0.buttons.contains { $0.label == "Add to Collection" && $0.isEnabled } }
        #expect(ready.buttons.first(labeled: "Add to Collection")?.hint == "Adds this import as one new item. Its receipt opens afterwards.")
        #expect(try await hosted.press("Add to Collection"))
        for _ in 0..<50 where opened.records.isEmpty { try await Task.sleep(for: .milliseconds(40)) }
        let receipt = try #require(opened.records.first)
        #expect(ReceiptPresentation(receipt).operation == "Create Item")
        #expect(ReceiptPresentation(receipt).adapter == "App UI")
        #expect(library.census?.user.items == 1)
    }
}

/// The receipts a review screen handed over, as the window's inspector would receive them.
@MainActor
final class OpenedReceipts {
    var records: [ReceiptRecord] = []
}
