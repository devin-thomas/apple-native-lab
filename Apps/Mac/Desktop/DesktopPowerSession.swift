import AppIntents
import AppKit
import DesktopNativePower
import LabDomain
import SwiftUI

/// Connects the allowlisted desktop intent to this host's store, and keeps the one station the
/// menus, the service, and that intent share.
@MainActor
enum DesktopPowerHost {
    private(set) static var session: DesktopPowerSession?

    @discardableResult
    static func connect(_ library: LabLibrary) -> DesktopPowerSession {
        let station = DesktopStation(backend: LibraryDesktopBackend(library: library))
        let session = DesktopPowerSession(station: station)
        self.session = session
        AppDependencyManager.shared.add(dependency: DesktopPowerLink(station: station))
        return session
    }
}

/// Notes and windows for every Mac scene. The station commits through `LabLibrary`.
@MainActor
@Observable
final class DesktopPowerSession {
    private(set) var notes: [DesktopDocument] = []
    private(set) var openWindowCount = 0
    private(set) var status = MenuBarStatus.empty
    private(set) var palette: [PaletteEntry] = DesktopCommand.palette(matching: "")
    private(set) var failure: String?
    private(set) var lastSummary: String?
    var selectedID: DesktopDocumentID?
    var paletteQuery = ""
    var showsPalette = false
    var showsFileImporter = false
    /// The next import is a private note: it is kept, and a later launch does not open its window.
    var importingPrivate = false
    /// Set when a document window should open. The main window observes it.
    var pendingDocumentID: String?

    let station: DesktopStation

    init(station: DesktopStation) {
        self.station = station
        refresh()
    }

    func refresh() {
        notes = station.notes()
        openWindowCount = station.openWindows().count
        status = station.status()
        palette = station.palette(matching: paletteQuery)
    }

    func reload() async {
        do {
            try await station.reload()
            failure = nil
        } catch {
            failure = error.description
        }
        refresh()
    }

    func restore(storageKey: String) {
        station.restore(storageKey: storageKey)
        refresh()
    }

    func restorableKey() -> String { station.sceneSnapshot().storageKey }

    func run(_ command: DesktopCommand) async {
        switch command {
        case .showPalette:
            showsPalette = true
        case .importSelectedText:
            await importPasteboard()
        case .importFile:
            showsFileImporter = true
        case .openDocumentWindow:
            openSelected()
        case .showStatus:
            refresh()
            lastSummary = status.summary
        case .resetFixtureState:
            station.resetFixtureState()
            lastSummary = "Fixture notes were removed. Imported notes are unchanged."
            refresh()
        case .importFixtureNote:
            await perform {
                let outcome = try await station.performAllowlisted(.importFixtureNote, as: .appUI)
                if case .imported(let imported) = outcome { self.noteImported(imported) }
            }
        }
    }

    func importPasteboard() async {
        let text = NSPasteboard.general.string(forType: .string)
        guard let text else {
            failure = DesktopPowerError.invalidText.description
            return
        }
        await importServiceText(text)
    }

    func importServiceText(_ text: String) async {
        let privacy: DocumentPrivacy = importingPrivate ? .privateContent : .ordinary
        await perform {
            let outcome = try await station.importSelectedText(text, privacy: privacy)
            self.noteImported(outcome)
        }
    }

    func importChosenFile(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        let data: Data
        do {
            data = try await Task.detached { try Data(contentsOf: url) }.value
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            failure = DesktopPowerError.invalidText.description
            return
        }
        if accessed { url.stopAccessingSecurityScopedResource() }
        let privacy: DocumentPrivacy = importingPrivate ? .privateContent : .ordinary
        await perform {
            let outcome = try await station.importFile(data, filename: url.lastPathComponent, privacy: privacy)
            self.noteImported(outcome)
        }
    }

    func importFileResult(_ result: Result<[URL], any Error>) async {
        switch result {
        case .failure:
            failure = DesktopPowerError.invalidText.description
        case .success(let urls):
            guard let url = urls.first else {
                failure = DesktopPowerError.emptyText.description
                return
            }
            await importChosenFile(url)
        }
    }

    func presentFixture() {
        do {
            let preview = try station.presentFixture()
            selectedID = preview.id
            failure = nil
            lastSummary = "Fixture preview. It is not in the lab until you import it."
        } catch {
            failure = error.description
        }
        refresh()
    }

    func open(_ id: DesktopDocumentID) {
        selectedID = id
        openSelected()
    }

    func openSelected() {
        guard let selectedID else {
            failure = DesktopPowerError.missingDocument.description
            return
        }
        do {
            _ = try station.openWindow(for: selectedID, explicit: true)
            pendingDocumentID = selectedID.rawValue
            failure = nil
        } catch {
            failure = error.description
        }
        refresh()
    }

    func close(window id: DesktopWindowID) {
        station.closeWindow(id)
        refresh()
    }

    func shouldPresent(_ id: DesktopDocumentID) -> Bool { station.shouldPresent(id) }

    private func noteImported(_ outcome: ImportOutcome) {
        selectedID = outcome.document.id
        pendingDocumentID = outcome.document.id.rawValue
        if let summary = outcome.receipt?.summary {
            lastSummary = summary
        } else if outcome.isReplay {
            lastSummary = "Already in this lab: \(outcome.document.title)."
        }
    }

    private func perform(_ body: () async throws -> Void) async {
        do {
            try await body()
            failure = nil
        } catch let error as DesktopPowerError {
            failure = error.description
        } catch {
            failure = DesktopPowerError.unavailable.description
        }
        refresh()
    }
}

/// The host's backend: every commit goes through `LabLibrary.submit`, as the app UI or as an App Intent.
struct LibraryDesktopBackend: DesktopBackend {
    let library: LabLibrary

    func collection(_ id: CollectionID, as adapter: AdapterKind) async throws(DesktopPowerError) -> LabCollection? {
        let actor = try scope(adapter)
        let service = try await opened()
        do {
            return try await service.collection(id, as: actor)
        } catch .notFound {
            return nil
        } catch {
            throw DesktopPowerError(error)
        }
    }

    func item(_ id: ItemID, as adapter: AdapterKind) async throws(DesktopPowerError) -> LabItem? {
        let actor = try scope(adapter)
        let service = try await opened()
        do {
            return try await service.item(id, as: actor)
        } catch .notFound {
            return nil
        } catch {
            throw DesktopPowerError(error)
        }
    }

    func items(in collectionID: CollectionID, as adapter: AdapterKind) async throws(DesktopPowerError) -> [LabItem] {
        let actor = try scope(adapter)
        let service = try await opened()
        do {
            let filter = try ItemFilter(collectionID: collectionID, includeArchived: true, limit: ItemFilter.allowedLimits.upperBound)
            return try await service.items(filter, as: actor)
        } catch let error as OperationError {
            throw DesktopPowerError(error)
        } catch {
            throw .unavailable
        }
    }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String],
        as adapter: AdapterKind
    ) async throws(DesktopPowerError) -> ActionReceipt {
        let authority = try authority(adapter)
        do {
            return try await library.submit(operation, requestID: requestID, authority: authority, names: names).receipt
        } catch {
            switch error {
            case .unavailable:
                throw .unavailable
            case .refused(let operationError):
                throw DesktopPowerError(operationError)
            }
        }
    }

    func receipt(for requestID: RequestID, as adapter: AdapterKind) async throws(DesktopPowerError) -> ActionReceipt? {
        let actor = try scope(adapter)
        let service = try await opened()
        do {
            return try await service.receipt(for: requestID, as: actor)
        } catch {
            throw DesktopPowerError(error)
        }
    }

    private func opened() async throws(DesktopPowerError) -> LabDataService {
        do {
            return try await library.openedService()
        } catch {
            throw .unavailable
        }
    }

    private func scope(_ adapter: AdapterKind) throws(DesktopPowerError) -> ActorScope {
        switch adapter {
        case .appUI: LabDataService.appUI
        case .appIntent: LabDataService.appIntent
        default: throw .notAuthorized
        }
    }

    private func authority(_ adapter: AdapterKind) throws(DesktopPowerError) -> CommitAuthority {
        switch adapter {
        case .appUI: .userAction
        case .appIntent: .intent(nil)
        default: throw .notAuthorized
        }
    }
}
