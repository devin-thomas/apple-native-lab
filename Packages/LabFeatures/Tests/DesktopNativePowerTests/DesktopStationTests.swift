import Foundation
import LabDomain
import Testing
@testable import DesktopNativePower

@MainActor
@Suite struct CommandCatalogTests {
    @Test func everyCommandHasAMenuAndAShortcut() {
        for command in DesktopCommand.allCases {
            #expect(!command.title.isEmpty)
            #expect(command.menuPath.contains(">"))
            #expect(!command.shortcut.isEmpty)
        }
        #expect(DesktopCommand.importFile.menuPath == "File > Import Desktop Note…")
        #expect(DesktopCommand.importSelectedText.menuPath == "Lab > Import Selected Text")
    }

    @Test func everyGestureHasADiscoverableAlternate() {
        #expect(DesktopGestures.everyGestureHasAMenuPath)
        let menus = Set(DesktopCommand.allCases.map(\.menuPath))
        for gesture in DesktopGestures.all {
            #expect(menus.contains(gesture.menuPath), "\(gesture.gesture) has no menu command")
        }
    }

    @Test func thePaletteFindsTheFileImport() {
        let matches = DesktopCommand.palette(matching: "import desktop")
        #expect(matches.map(\.command) == [.importFile])
        #expect(DesktopCommand.palette(matching: "").count == DesktopCommand.allCases.count)
    }

    @Test func theMenuBarStatusDoesNotQuoteANote() {
        let status = MenuBarStatus(noteCount: 2, windowCount: 1, summary: MenuBarStatus.sentence(notes: 2, windows: 1))
        #expect(status.summary == "2 notes, 1 window")
        #expect(MenuBarStatus.sentence(notes: 1, windows: 0) == "1 note, 0 windows")
    }
}

@MainActor
@Suite struct ScriptAdmissionTests {
    @Test func onlyTheAllowlistIsAdmitted() throws {
        #expect(try ScriptAdmission.admit("import-fixture-note") == .importFixtureNote)
        #expect(try ScriptAdmission.admit("  show-status  ") == .showStatus)
        #expect(Set(ScriptableCommand.allCases.map(\.rawValue)) == ["import-fixture-note", "show-status"])
    }

    @Test func shellTextIsRefused() {
        for sample in ["rm -rf /", "ls | sh", "import-fixture-note; whoami", "$(whoami)", "cat < /etc/passwd", "echo `id`"] {
            #expect(throws: DesktopPowerError.shellRefused) { try ScriptAdmission.admit(sample) }
        }
    }

    @Test func anUnknownTokenIsRefused() {
        #expect(throws: DesktopPowerError.unknownCommand("format-disk")) {
            try ScriptAdmission.admit("format-disk")
        }
    }

    @Test func theIntentEnumIsTheSameAllowlist() {
        #expect(Set(AllowlistedDesktopCommand.allCases.map(\.rawValue)) == Set(ScriptableCommand.allCases.map(\.rawValue)))
        #expect(AllowlistedDesktopCommand.importFixtureNote.command == .importFixtureNote)
    }
}

@MainActor
@Suite struct DesktopStationTests {
    @Test func importingSelectedTextCommitsAReceiptAndKeepsTheNoteAfterTheWindowCloses() async throws {
        let lab = Lab.make()
        let outcome = try await lab.station.importSelectedText("Buoy count\nTwelve, and no names.")
        let receipt = try #require(outcome.receipt)
        #expect(receipt.status == .committed)
        #expect(receipt.admitted.adapter == .appUI)
        #expect(outcome.document.title == "Buoy count")
        #expect(outcome.document.origin == .selectedText)
        #expect(outcome.isReplay == false)

        lab.station.closeWindow(outcome.window.id)
        #expect(lab.station.openWindows().isEmpty)
        #expect(lab.station.notes().map(\.id) == [outcome.document.id])
        let item = try #require(await lab.backend.item(outcome.document.itemID!, as: .appUI))
        #expect(item.note.value == "Buoy count\nTwelve, and no names.")
        #expect(item.namespace == .user)
    }

    @Test func twoWindowsCanCloseWithoutLosingTheNote() async throws {
        let lab = Lab.make()
        let outcome = try await lab.station.importSelectedText("Pier log\nOne line.")
        let second = try lab.station.openWindow(for: outcome.document.id, explicit: true)
        lab.station.closeWindow(outcome.window.id)
        #expect(lab.station.openWindows().map(\.id) == [second.id])
        #expect(lab.station.notes().count == 1)
        lab.station.closeWindow(second.id)
        #expect(lab.station.notes().count == 1)
        #expect(try await lab.backend.item(outcome.document.itemID!, as: .appUI) != nil)
    }

    @Test func aFileImportIsTheMenuFallback() async throws {
        let lab = Lab.make()
        let data = try DesktopFixture.data()
        let outcome = try await lab.station.importFile(data, filename: "sample-desk-note.txt")
        #expect(outcome.document.title == "Harbor tally")
        #expect(outcome.document.origin == .fileImport)
        #expect(outcome.receipt?.admitted.adapter == .appUI)
        #expect(DesktopCommand.importFile.menuPath == "File > Import Desktop Note…")
        lab.station.closeWindow(outcome.window.id)
        #expect(lab.station.notes().count == 1)
    }

    @Test func importingTheSameTextAgainDoesNotCreateAnotherItem() async throws {
        let lab = Lab.make()
        let first = try await lab.station.importSelectedText("Same note\nOnce.")
        lab.station.closeWindow(first.window.id)
        let second = try await lab.station.importSelectedText("Same note\nOnce.")
        #expect(second.isReplay)
        #expect(second.document.itemID == first.document.itemID)
        #expect(lab.station.notes().count == 1)
        let items = try await lab.backend.items(in: DesktopIdentity.collectionID, as: .appUI)
        #expect(items.count == 1)
    }

    @Test func aCancelledImportCommitsNothing() async throws {
        let lab = Lab.make()
        await #expect(throws: DesktopPowerError.cancelled) {
            try await lab.station.importSelectedText("Gone\nNever stored.", isCancelled: { true })
        }
        #expect(lab.station.notes().isEmpty)
        #expect(try await lab.backend.collection(DesktopIdentity.collectionID, as: .appUI) == nil)
    }

    @Test func invalidTextCommitsNothing() async throws {
        let lab = Lab.make()
        await #expect(throws: DesktopPowerError.emptyText) {
            try await lab.station.importSelectedText("  \n\t")
        }
        await #expect(throws: DesktopPowerError.invalidText) {
            try await lab.station.importSelectedText("Bad\n\u{0001}")
        }
        await #expect(throws: DesktopPowerError.invalidText) {
            try await lab.station.importFile(Data([0xFF, 0xFE]), filename: "notes.txt")
        }
        let tooLong = String(repeating: "a", count: ItemNote.maximumLength + 1)
        await #expect(throws: DesktopPowerError.textTooLong(limit: ItemNote.maximumLength)) {
            try await lab.station.importSelectedText(tooLong)
        }
        #expect(lab.station.notes().isEmpty)
        #expect(try await lab.backend.collection(DesktopIdentity.collectionID, as: .appUI) == nil)
    }

    @Test func anUnavailableStoreCommitsNothing() async throws {
        let station = DesktopStation(backend: UnavailableDesktopBackend())
        await #expect(throws: DesktopPowerError.unavailable) {
            try await station.importSelectedText("Pier log\nOne line.")
        }
        #expect(station.notes().isEmpty)
        #expect(station.openWindows().isEmpty)
    }

    @Test func aModelToolCannotCommit() async throws {
        let lab = Lab.make()
        await #expect(throws: DesktopPowerError.notAuthorized) {
            try await lab.station.importSelectedText("Pier log\nOne line.", as: .modelTool)
        }
        #expect(lab.station.notes().isEmpty)
        #expect(try await lab.backend.collection(DesktopIdentity.collectionID, as: .appUI) == nil)
    }

    @Test func shellTextFromAScriptCommitsNothingAndIsNotRun() async throws {
        let lab = Lab.make()
        await #expect(throws: DesktopPowerError.shellRefused) {
            try await lab.station.performScriptText("rm -rf /", as: .appIntent)
        }
        await #expect(throws: DesktopPowerError.shellRefused) {
            try await lab.station.performScriptText("import-fixture-note; whoami", as: .appIntent)
        }
        #expect(lab.station.notes().isEmpty)
        #expect(try await lab.backend.collection(DesktopIdentity.collectionID, as: .appUI) == nil)
    }

    @Test func selectedTextThatLooksLikeAShellIsStoredAndNotRun() async throws {
        let lab = Lab.make()
        let outcome = try await lab.station.importSelectedText("rm -rf /\nkept as a note")
        #expect(outcome.document.body == "rm -rf /\nkept as a note")
        #expect(outcome.receipt?.status == .committed)
        #expect(lab.station.notes().count == 1)
    }

    @Test func theAllowlistedIntentImportsTheFixtureAsAnAppIntent() async throws {
        let lab = Lab.make()
        let outcome = try await lab.station.performAllowlisted(.importFixtureNote, as: .appIntent)
        guard case .imported(let imported) = outcome else {
            Issue.record("expected an import")
            return
        }
        #expect(imported.receipt?.admitted.adapter == .appIntent)
        #expect(imported.document.title == "Harbor tally")
        #expect(imported.document.origin == .script)
        let again = try await lab.station.performAllowlisted(.importFixtureNote, as: .appIntent)
        guard case .imported(let replay) = again else {
            Issue.record("expected a replay")
            return
        }
        #expect(replay.isReplay)
        #expect(replay.document.itemID == imported.document.itemID)
        let items = try await lab.backend.items(in: DesktopIdentity.collectionID, as: .appUI)
        #expect(items.count == 1)
    }

    @Test func aSecondEntryPointJoinsTheExistingNote() async throws {
        let lab = Lab.make()
        _ = try await lab.station.performAllowlisted(.importFixtureNote, as: .appUI)
        let second = try await lab.station.performAllowlisted(.importFixtureNote, as: .appIntent)
        guard case .imported(let imported) = second else {
            Issue.record("expected an import")
            return
        }
        #expect(imported.isReplay)
        #expect(imported.receipt == nil)
        let items = try await lab.backend.items(in: DesktopIdentity.collectionID, as: .appUI)
        #expect(items.count == 1)
    }

    @Test func showStatusDoesNotCommit() async throws {
        let lab = Lab.make()
        let outcome = try await lab.station.performAllowlisted(.showStatus, as: .appIntent)
        guard case .status(let status) = outcome else {
            Issue.record("expected a status")
            return
        }
        #expect(status.summary == "0 notes, 0 windows")
        #expect(try await lab.backend.collection(DesktopIdentity.collectionID, as: .appUI) == nil)
    }

    @Test func closingWindowsDoesNotRestoreAPrivateNote() async throws {
        let lab = Lab.make()
        let ordinary = try await lab.station.importSelectedText("Public tally\nVisible.")
        let secret = "dock-key-1844"
        let privateNote = try await lab.station.importSelectedText("\(secret)\nDo not restore this body.", privacy: .privateContent)
        #expect(lab.station.shouldPresent(privateNote.document.id))
        let snapshot = lab.station.sceneSnapshot()
        #expect(snapshot.openDocumentIDs == [ordinary.document.id])
        #expect(snapshot.withheldPrivateDocumentIDs == [privateNote.document.id])
        #expect(!snapshot.contains(secret))
        #expect(!snapshot.contains(privateNote.document.body))
        #expect(!lab.station.status().summary.contains(secret))

        lab.station.discardSessionWindows()
        #expect(lab.station.notes().count == 2)
        #expect(lab.station.shouldPresent(privateNote.document.id) == false)
        #expect(lab.station.shouldPresent(ordinary.document.id))

        let hostile = SceneSnapshot(
            openDocumentIDs: [ordinary.document.id, privateNote.document.id],
            withheldPrivateDocumentIDs: []
        )
        lab.station.restore(hostile)
        #expect(lab.station.openWindows().map(\.documentID) == [ordinary.document.id])
        #expect(lab.station.shouldPresent(privateNote.document.id) == false)
        #expect(throws: DesktopPowerError.privateContentWithheld) {
            try lab.station.openWindow(for: privateNote.document.id, explicit: false)
        }
        let opened = try lab.station.openWindow(for: privateNote.document.id, explicit: true)
        #expect(lab.station.shouldPresent(privateNote.document.id))
        lab.station.closeWindow(opened.id)
        #expect(lab.station.note(privateNote.document.id) != nil)
    }

    @Test func reloadKeepsCommittedNotesAndDoesNotOpenPrivateOnes() async throws {
        let lab = Lab.make()
        let ordinary = try await lab.station.importFile(try DesktopFixture.data(), filename: "sample-desk-note.txt")
        let secret = "night-ledger"
        _ = try await lab.station.importSelectedText("\(secret)\nPrivate body.", privacy: .privateContent)
        let key = lab.station.sceneSnapshot().storageKey
        #expect(!key.contains(secret))

        let revived = DesktopStation(backend: lab.backend)
        try await revived.reload()
        #expect(revived.openWindows().isEmpty)
        #expect(revived.notes().map(\.title).sorted() == ["Harbor tally", secret])
        let privateID = try #require(revived.notes().first { $0.privacy == .privateContent }?.id)
        #expect(revived.shouldPresent(privateID) == false)
        revived.restore(storageKey: key)
        #expect(revived.openWindows().map(\.documentID) == [ordinary.document.id])
        #expect(revived.shouldPresent(privateID) == false)
    }

    @Test func resetRemovesOnlyTheFixturePreview() async throws {
        let lab = Lab.make()
        let preview = try lab.station.presentFixture()
        #expect(preview.itemID == nil)
        #expect(try await lab.backend.collection(DesktopIdentity.collectionID, as: .appUI) == nil)
        let imported = try await lab.station.importSelectedText("Kept\nAfter reset.")
        _ = try lab.station.openWindow(for: preview.id, explicit: true)
        lab.station.resetFixtureState()
        #expect(lab.station.notes().map(\.id) == [imported.document.id])
        #expect(lab.station.openWindows().allSatisfy { $0.documentID == imported.document.id })
        #expect(try await lab.backend.item(imported.document.itemID!, as: .appUI) != nil)
    }
}

@MainActor
private struct Lab {
    let backend: ServiceDesktopBackend
    let station: DesktopStation

    static func make() -> Lab {
        let store = InMemoryOperationStore()
        let service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: GrantLedger()))
        let backend = ServiceDesktopBackend(service: service)
        return Lab(backend: backend, station: DesktopStation(backend: backend))
    }
}
