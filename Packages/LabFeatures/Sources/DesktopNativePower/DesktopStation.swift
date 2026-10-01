import Foundation
import LabDomain

/// What committing a note left behind: the document, the window onto it, and the receipt when
/// this entry point is the one that committed it.
public struct ImportOutcome: Hashable, Sendable {
    public let document: DesktopDocument
    public let window: DesktopWindow
    /// `nil` when the note was already committed by another entry point. That commit has its own receipt.
    public let receipt: ActionReceipt?
    public let isReplay: Bool

    public init(document: DesktopDocument, window: DesktopWindow, receipt: ActionReceipt?, isReplay: Bool) {
        self.document = document
        self.window = window
        self.receipt = receipt
        self.isReplay = isReplay
    }
}

/// The result of an allowlisted command. A status read has no receipt.
public enum ScriptOutcome: Hashable, Sendable {
    case status(MenuBarStatus)
    case imported(ImportOutcome)
}

/// The notes, windows, and scene for Desktop Native Power.
///
/// Imports commit through `DesktopBackend` as the adapter that asked, so a menu and the allowlisted
/// intent share the operation service's authorization and receipts. Closing a window removes the
/// window only. A private note can be open because someone opened it in this session; a restored
/// scene does not open one.
@MainActor
public final class DesktopStation {
    private let backend: any DesktopBackend
    private var documents: [DesktopDocumentID: DesktopDocument] = [:]
    private var order: [DesktopDocumentID] = []
    private var windows: [DesktopWindow] = []
    private var explicit: Set<DesktopDocumentID> = []
    private var nextWindow = 1

    public init(backend: any DesktopBackend) {
        self.backend = backend
    }

    public func notes() -> [DesktopDocument] {
        order.compactMap { documents[$0] }
    }

    public func openWindows() -> [DesktopWindow] { windows }

    public func note(_ id: DesktopDocumentID) -> DesktopDocument? { documents[id] }

    public func status() -> MenuBarStatus {
        MenuBarStatus(
            noteCount: notes().count,
            windowCount: windows.count,
            summary: MenuBarStatus.sentence(notes: notes().count, windows: windows.count)
        )
    }

    public func palette(matching query: String) -> [PaletteEntry] {
        DesktopCommand.palette(matching: query)
    }

    /// Shows the bundled fixture as a preview. It is not a lab item, and Reset Fixture Notes removes only this.
    @discardableResult
    public func presentFixture() throws(DesktopPowerError) -> DesktopDocument {
        if let existing = documents[DesktopIdentity.fixtureDocumentID] { return existing }
        let text = try DesktopFixture.text()
        let note = try DesktopNoteParser.parse(text, fallbackTitle: "Harbor tally")
        let document = DesktopDocument(
            id: DesktopIdentity.fixtureDocumentID,
            title: note.title.value,
            body: note.body.value,
            privacy: .ordinary,
            origin: .fixture,
            itemID: nil
        )
        remember(document)
        return document
    }

    /// Removes fixture previews and the windows onto them. Imported notes and lab items stay.
    public func resetFixtureState() {
        let fixtureIDs = Set(notes().filter { $0.origin == .fixture }.map(\.id))
        for id in fixtureIDs {
            documents[id] = nil
            explicit.remove(id)
        }
        order.removeAll { fixtureIDs.contains($0) }
        windows.removeAll { fixtureIDs.contains($0.documentID) }
    }

    @discardableResult
    public func openWindow(for id: DesktopDocumentID, explicit isExplicit: Bool) throws(DesktopPowerError) -> DesktopWindow {
        guard let document = documents[id] else { throw .missingDocument }
        if document.privacy == .privateContent && !isExplicit { throw .privateContentWithheld }
        if isExplicit { explicit.insert(id) }
        let window = DesktopWindow(id: DesktopWindowID(rawValue: "window-\(nextWindow)"), documentID: id)
        nextWindow += 1
        windows.append(window)
        return window
    }

    /// Drops the window. The document stays, and so does its lab item.
    public func closeWindow(_ id: DesktopWindowID) {
        guard let window = windows.first(where: { $0.id == id }) else { return }
        windows.removeAll { $0.id == id }
        if !windows.contains(where: { $0.documentID == window.documentID }) {
            explicit.remove(window.documentID)
        }
    }

    /// True when a window may show this note's text. A private note qualifies only after an
    /// explicit open in this session.
    public func shouldPresent(_ id: DesktopDocumentID) -> Bool {
        guard let document = documents[id] else { return false }
        if document.privacy == .ordinary { return true }
        return explicit.contains(id)
    }

    public func sceneSnapshot() -> SceneSnapshot {
        var open: [DesktopDocumentID] = []
        var withheld: [DesktopDocumentID] = []
        var seen = Set<DesktopDocumentID>()
        for window in windows {
            guard seen.insert(window.documentID).inserted, let document = documents[window.documentID] else { continue }
            if document.privacy == .privateContent {
                withheld.append(document.id)
            } else {
                open.append(document.id)
            }
        }
        return SceneSnapshot(openDocumentIDs: open, withheldPrivateDocumentIDs: withheld)
    }

    /// Opens windows for ordinary notes named in the snapshot. A private ID in the open list is skipped.
    public func restore(_ snapshot: SceneSnapshot) {
        let privateIDs = Set(notes().filter { $0.privacy == .privateContent }.map(\.id))
        for id in snapshot.openDocumentIDs where documents[id] != nil && !privateIDs.contains(id) {
            _ = try? openWindow(for: id, explicit: false)
        }
    }

    public func restore(storageKey: String) {
        let ids = storageKey.split(separator: ",").map { DesktopDocumentID(rawValue: String($0)) }
        restore(SceneSnapshot(openDocumentIDs: ids.filter { !$0.rawValue.isEmpty }, withheldPrivateDocumentIDs: []))
    }

    /// Forgets which windows were open, as a relaunch does. Documents stay.
    public func discardSessionWindows() {
        windows.removeAll()
        explicit.removeAll()
    }

    public func importSelectedText(
        _ text: String,
        privacy: DocumentPrivacy = .ordinary,
        as adapter: AdapterKind = .appUI,
        isCancelled: @Sendable () -> Bool = { false }
    ) async throws(DesktopPowerError) -> ImportOutcome {
        let note = try DesktopNoteParser.parse(text, fallbackTitle: "Desktop note")
        return try await commit(note, origin: .selectedText, privacy: privacy, as: adapter, isCancelled: isCancelled)
    }

    public func importFile(
        _ data: Data,
        filename: String,
        privacy: DocumentPrivacy = .ordinary,
        as adapter: AdapterKind = .appUI,
        isCancelled: @Sendable () -> Bool = { false }
    ) async throws(DesktopPowerError) -> ImportOutcome {
        let note = try DesktopNoteParser.parseFile(data, filename: filename)
        return try await commit(note, origin: .fileImport, privacy: privacy, as: adapter, isCancelled: isCancelled)
    }

    public func performAllowlisted(
        _ command: ScriptableCommand,
        as adapter: AdapterKind,
        isCancelled: @Sendable () -> Bool = { false }
    ) async throws(DesktopPowerError) -> ScriptOutcome {
        switch command {
        case .showStatus:
            return .status(status())
        case .importFixtureNote:
            let text = try DesktopFixture.text()
            let note = try DesktopNoteParser.parse(text, fallbackTitle: "Harbor tally")
            let outcome = try await commit(note, origin: .script, privacy: .ordinary, as: adapter, isCancelled: isCancelled)
            return .imported(outcome)
        }
    }

    /// Admits `raw` or refuses it, then runs only an admitted command. Shell text never reaches a commit.
    public func performScriptText(
        _ raw: String,
        as adapter: AdapterKind,
        isCancelled: @Sendable () -> Bool = { false }
    ) async throws(DesktopPowerError) -> ScriptOutcome {
        let command = try ScriptAdmission.admit(raw)
        return try await performAllowlisted(command, as: adapter, isCancelled: isCancelled)
    }

    /// Rebuilds committed notes from the desktop collection. Fixture previews already in memory stay.
    /// Windows the caller did not ask to restore stay closed.
    public func reload(as adapter: AdapterKind = .appUI) async throws(DesktopPowerError) {
        let items = try await backend.items(in: DesktopIdentity.collectionID, as: adapter)
        let previews = notes().filter { $0.itemID == nil }
        var kept: [DesktopDocumentID: DesktopDocument] = [:]
        var keptOrder: [DesktopDocumentID] = []
        for preview in previews {
            kept[preview.id] = preview
            keptOrder.append(preview.id)
        }
        for item in items {
            guard let mark = DesktopIdentity.mark(in: item.extras) else { continue }
            let document = DesktopDocument(
                id: DesktopIdentity.documentID(for: item.id),
                title: item.title.value,
                body: item.note.value,
                privacy: mark.privacy,
                origin: mark.origin,
                itemID: item.id
            )
            if kept[document.id] == nil { keptOrder.append(document.id) }
            kept[document.id] = document
        }
        documents = kept
        order = keptOrder
        windows.removeAll { documents[$0.documentID] == nil }
        explicit = explicit.filter { documents[$0] != nil }
    }

    // MARK: Committing

    private func commit(
        _ note: DesktopNote,
        origin: DocumentOrigin,
        privacy: DocumentPrivacy,
        as adapter: AdapterKind,
        isCancelled: @Sendable () -> Bool
    ) async throws(DesktopPowerError) -> ImportOutcome {
        if isCancelled() { throw .cancelled }
        let text = note.body.value
        let itemID = DesktopIdentity.itemID(text: text, origin: origin, privacy: privacy)
        let requestID = DesktopIdentity.requestID(text: text, origin: origin, privacy: privacy, adapter: adapter)
        if let receipt = try await backend.receipt(for: requestID, as: adapter) {
            return try finish(note, itemID: itemID, origin: origin, privacy: privacy, receipt: receipt, isReplay: true)
        }
        if isCancelled() { throw .cancelled }
        try await ensureCollection(as: adapter, isCancelled: isCancelled)
        if isCancelled() { throw .cancelled }
        let extras = try DesktopIdentity.extras(origin: origin, privacy: privacy)
        let draft = ItemDraft(
            id: itemID,
            in: DesktopIdentity.collectionID,
            title: note.title,
            note: note.body,
            extras: extras
        )
        let names: [EntityReference: String] = [
            .collection(DesktopIdentity.collectionID): DesktopIdentity.collectionTitle,
            .item(itemID): note.title.value,
        ]
        do {
            let receipt = try await backend.commit(
                .createItem(draft: draft),
                requestID: requestID,
                names: names,
                as: adapter
            )
            return try finish(note, itemID: itemID, origin: origin, privacy: privacy, receipt: receipt, isReplay: false)
        } catch .alreadyStored {
            guard let item = try await backend.item(itemID, as: adapter) else { throw .alreadyStored }
            let document = document(from: item)
            remember(document)
            let window = try openWindow(for: document.id, explicit: true)
            return ImportOutcome(document: document, window: window, receipt: nil, isReplay: true)
        }
    }

    private func finish(
        _ note: DesktopNote,
        itemID: ItemID,
        origin: DocumentOrigin,
        privacy: DocumentPrivacy,
        receipt: ActionReceipt,
        isReplay: Bool
    ) throws(DesktopPowerError) -> ImportOutcome {
        let document = DesktopDocument(
            id: DesktopIdentity.documentID(for: itemID),
            title: note.title.value,
            body: note.body.value,
            privacy: privacy,
            origin: origin,
            itemID: itemID
        )
        remember(document)
        let window = try openWindow(for: document.id, explicit: true)
        return ImportOutcome(document: document, window: window, receipt: receipt, isReplay: isReplay)
    }

    private func ensureCollection(as adapter: AdapterKind, isCancelled: @Sendable () -> Bool) async throws(DesktopPowerError) {
        if try await backend.collection(DesktopIdentity.collectionID, as: adapter) != nil { return }
        if isCancelled() { throw .cancelled }
        let title: EntityTitle
        do {
            title = try EntityTitle(DesktopIdentity.collectionTitle)
        } catch {
            throw .invalidText
        }
        let draft = CollectionDraft(id: DesktopIdentity.collectionID, title: title)
        do {
            _ = try await backend.commit(
                .createCollection(draft: draft),
                requestID: DesktopIdentity.collectionRequestID,
                names: [.collection(DesktopIdentity.collectionID): DesktopIdentity.collectionTitle],
                as: adapter
            )
        } catch .alreadyStored {
            return
        }
    }

    private func document(from item: LabItem) -> DesktopDocument {
        let mark = DesktopIdentity.mark(in: item.extras)
        return DesktopDocument(
            id: DesktopIdentity.documentID(for: item.id),
            title: item.title.value,
            body: item.note.value,
            privacy: mark?.privacy ?? .ordinary,
            origin: mark?.origin ?? .selectedText,
            itemID: item.id
        )
    }

    private func remember(_ document: DesktopDocument) {
        if documents[document.id] == nil { order.append(document.id) }
        documents[document.id] = document
    }
}
