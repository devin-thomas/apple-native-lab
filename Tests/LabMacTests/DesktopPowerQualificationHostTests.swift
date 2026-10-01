import AppKit
import CryptoKit
import DesktopNativePower
import Foundation
import LabDomain
import LabStore
import LabSupport
import SwiftUI
import Testing
@testable import NativeLab

/// The real Mac adapters on a fresh SQLite store. Calls handlers directly; no system menu,
/// document scene, file dialog, Shortcuts, or assistive technology is driven by this replay.
@MainActor
@Suite(.serialized)
struct DesktopPowerQualificationHostTests {
    @Test func theHostedReplayPreservesImportedNotesAndReceipts() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "DesktopPowerQualification-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let session = DesktopPowerHost.connect(library)
        let bytes = try DesktopFixture.data()
        let file = folder.appending(path: "sample-desk-note.txt")
        try bytes.write(to: file)
        var observations: [String] = []
        var failures: [String] = []
        func check(_ matches: Bool, _ detail: String) {
            #expect(matches, "\(detail)")
            if matches { observations.append(detail) } else { failures.append(detail) }
        }

        session.presentFixture()
        check(session.notes.count == 1 && session.notes[0].itemID == nil, "fixture preview is not committed")
        await session.run(.importFile)
        check(session.showsFileImporter, "file command requests the native file importer")
        await session.importFileResult(.success([file]))
        let imported = try #require(session.notes.first { $0.itemID != nil })
        let itemID = try #require(imported.itemID)
        check(imported.origin == .fileImport && imported.body == String(decoding: bytes, as: UTF8.self), "chosen-file handler imports the original bytes")
        let receipt = try #require(library.receipts.first { $0.receipt.affectedEntities == [.item(itemID)] }?.receipt)
        check(receipt.status == .committed && receipt.admitted.adapter == .appUI, "file import commits an app-UI receipt")
        let fileReceiptCount = library.receipts.count
        await session.importFileResult(.success([file]))
        check(library.receipts.count == fileReceiptCount && session.notes.filter { $0.itemID == itemID }.count == 1, "reimporting the file keeps one item and adds no receipt")
        await session.run(.importFixtureNote)
        check(library.receipts.count == fileReceiptCount + 1, "script-origin import is a separate item from file-origin import")
        let receiptCount = library.receipts.count
        await session.run(.importFixtureNote)
        check(library.receipts.count == receiptCount, "menu replay adds no receipt")
        var intent = RunDesktopCommandIntent()
        intent.command = .importFixtureNote
        _ = try await intent.run(with: DesktopPowerLink(station: session.station))
        check(library.receipts.count == receiptCount, "intent replay adds no receipt")
        intent.command = .showStatus
        _ = try await intent.run(with: DesktopPowerLink(station: session.station))
        check(library.receipts.count == receiptCount, "intent status does not commit")
        await #expect(throws: DesktopPowerError.unavailable) { try await intent.run(with: .unavailable) }

        for window in session.station.openWindows() { session.close(window: window.id) }
        check(session.openWindowCount == 0 && session.notes.contains { $0.id == imported.id }, "session close handler keeps the document")
        session.selectedID = imported.id
        await session.run(.openDocumentWindow)
        check(session.pendingDocumentID == imported.id.rawValue, "alternate command requests the selected document scene")
        session.paletteQuery = "import desktop"
        session.refresh()
        check(session.palette.map(\.command) == [.importFile], "palette finds the file fallback")
        await session.run(.resetFixtureState)
        check(session.notes.count == 2 && session.notes.allSatisfy { $0.itemID != nil }, "fixture reset removes only the preview")

        let beforeFailures = library.receipts.count
        await session.importFileResult(.failure(CocoaError(.userCancelled)))
        check(session.failure != nil && library.receipts.count == beforeFailures, "cancelled file result reports an error and commits nothing")
        await session.importServiceText(" \n\t")
        check(session.failure != nil && library.receipts.count == beforeFailures, "empty selected text is refused")
        await #expect(throws: DesktopPowerError.notAuthorized) {
            try await session.station.importSelectedText("Denied fixture\nNo write.", as: .modelTool)
        }
        await #expect(throws: DesktopPowerError.cancelled) {
            try await session.station.importSelectedText("Cancelled fixture\nNo write.", isCancelled: { true })
        }
        await #expect(throws: DesktopPowerError.shellRefused) {
            try await session.station.performScriptText("import-fixture-note; whoami", as: .appIntent)
        }
        check(library.receipts.count == beforeFailures, "denial, cancellation, and shell refusal add no receipt")

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Service fixture\nOriginal selected text.", forType: .string)
        var serviceError: NSString?
        DesktopServiceProvider.shared.importSelectedText(pasteboard, userData: "", error: &serviceError)
        for _ in 0..<100 where !session.notes.contains(where: { $0.title == "Service fixture" }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        check(serviceError == nil && session.notes.contains { $0.title == "Service fixture" && $0.origin == .selectedText }, "Services handler reads a dedicated pasteboard and commits through the host")
        pasteboard.clearContents()
        DesktopServiceProvider.shared.importSelectedText(pasteboard, userData: "", error: &serviceError)
        check(serviceError != nil, "Services handler reports missing text synchronously")

        session.importingPrivate = true
        await session.importServiceText("Private fixture\nOriginal, no personal data.")
        let privateNote = try #require(session.notes.first { $0.privacy == .privateContent })
        let routes = session.restorableKey()
        check(!routes.contains(privateNote.id.rawValue), "scene storage omits the private document ID")
        let revived = DesktopPowerSession(station: DesktopStation(backend: LibraryDesktopBackend(library: library)))
        await revived.reload()
        revived.restore(storageKey: privateNote.id.rawValue)
        check(revived.openWindowCount == 0 && !revived.shouldPresent(privateNote.id), "fresh session refuses a stale private route")
        _ = await library.resetDemo()
        await revived.reload()
        let store = try await SQLiteOperationStore(url: storeURL)
        let persisted = try await store.items(in: nil)
        check(persisted.filter { $0.namespace == .user }.count == 4, "Reset Demo preserves all four imported notes")
        check(try await store.receipt(for: receipt.requestID) == receipt, "SQLite preserves the file import receipt")
        check(revived.notes.count == 4 && revived.notes.contains { $0.id == imported.id }, "reload retains the document after close and reset")

        let record = try EvidenceRecord(
            subject: "LAB-042",
            check: "Desktop Native Power hosted fixture replay through Mac file, Services, session, and intent adapters",
            date: Date(), provenance: .current, execution: .fixture,
            inputs: ["sample-desk-note.txt@sha256:\(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())"],
            steps: ["DesktopPowerQualificationHostTests on LabMac-Core, fresh SQLite store and temporary original fixture file", "Preview; chosen-file handler; menu and intent replay; close handler; alternate command; palette; fixture reset", "Cancelled file result; empty text; model denial; cancellation; shell refusal; Services handler on dedicated pasteboard", "Private note; fresh session reload; stale private route; Reset Demo; direct SQLite read"],
            outcome: failures.isEmpty ? .passed(observed: "\(observations.count) observations matched: " + observations.joined(separator: "; ")) : .failed(observed: failures.joined(separator: "; ")),
            limitations: ["Fixture only: handlers invoked in the sandboxed Mac host, not a person or a system menu invocation.", "No document window was actually opened or closed. The session close handler is tested; native window lifecycle is unverified.", "No file dialog, menu-bar interaction, Shortcuts, Siri, VoiceOver, Voice Control, Full Keyboard Access, physical mobile device, or 26-SDK compile.", "The cancelled file picker result is presented as invalid text by the current session. The Services handler completes asynchronously; its error pointer covers admission only."]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        Attachment.record(String(decoding: try encoder.encode(record), as: UTF8.self), named: "LAB-042-desktop-host-replay.json")
        #expect(record.result == .passed)
        #expect(record.provenance.xcodeBuild != "unknown")
    }

    @Test func everyDesktopCommandExistsInTheRunningAppsMenus() throws {
        func items(_ menu: NSMenu?) -> [NSMenuItem] {
            guard let menu else { return [] }
            menu.delegate?.menuNeedsUpdate?(menu)
            menu.update()
            return menu.items.flatMap { [$0] + items($0.submenu) }
        }
        let menus = items(NSApp.mainMenu)
        for command in DesktopCommand.allCases {
            let item = try #require(menus.first { $0.title == command.title && !$0.keyEquivalent.isEmpty })
            #expect(!item.isHidden)
            #expect(command.menuPath.hasPrefix("\(item.menu?.title ?? "missing") >"))
        }
    }

    @Test func thePaletteExposesItsAlternatePathsAndCloseButton() async throws {
        let session = DesktopPowerSession(station: DesktopStation(backend: UnavailableDesktopBackend()))
        let hosted = HostedView(DesktopPaletteSheet().environment(session), size: CGSize(width: 560, height: 700))
        defer { hosted.close() }
        let tree = try await hosted.tree()
        #expect(tree.buttons.contains { $0.label == "Close" })
        for command in DesktopCommand.allCases {
            #expect(tree.contains { $0.label.contains(command.title) })
        }
    }

    @Test func theIntentCommitsAsAnIntentOnAFreshStore() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "DesktopIntentQualification-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = LabLibrary(locateStore: { folder.appending(path: LabStoreLocation.fileName) })
        await library.start()
        try #require(library.phase == .ready)
        let station = DesktopStation(backend: LibraryDesktopBackend(library: library))
        var intent = RunDesktopCommandIntent()
        intent.command = .importFixtureNote
        _ = try await intent.run(with: DesktopPowerLink(station: station))
        let itemID = try #require(station.notes().first?.itemID)
        let receipt = try #require(library.receipts.first { $0.receipt.affectedEntities == [.item(itemID)] }?.receipt)
        #expect(receipt.status == .committed)
        #expect(receipt.admitted.adapter == .appIntent)
        #expect(receipt.admitted.operation.kind == .createItem)
    }
}
