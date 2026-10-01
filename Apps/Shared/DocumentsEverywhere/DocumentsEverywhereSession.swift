import DocumentsEverywhere
import Foundation
import LabDomain
import Observation
import PortableObjects

/// LAB-009 Documents Everywhere in one window: browse sample documents, preview them without the
/// File Provider, and optionally adopt one into the lab through Portable Objects' importer.
@MainActor
@Observable
final class DocumentsEverywhereSession {
    enum Phase: Hashable {
        case notStarted
        case ready
        case unavailable(String)
    }

    struct Entry: Hashable, Identifiable {
        var id: ProviderItemID { item.id }
        let item: ProviderItem
        let sample: SampleDocument
    }

    enum Outcome: Hashable {
        case previewed(DocumentPreview)
        case adopted(ImportResult)
        case refused(String)
        case cancelled
    }

    private(set) var phase: Phase = .notStarted
    private(set) var entries: [Entry] = []
    private(set) var destinations: [LabCollection] = []
    var destinationID: CollectionID?
    var selectedID: ProviderItemID?
    private(set) var preview: DocumentPreview?
    private(set) var outcome: Outcome?
    private(set) var providerState: ProviderConnectionState = .disabled
    /// Always reports that the File Provider stays off in this build.
    let providerStatusMessage = "The sample File Provider stays disabled until LAB-009-B qualifies it. Previews use the document browser and Quick Look, not the provider."

    @ObservationIgnored private var catalog = SampleCatalog.bundled
    @ObservationIgnored private var importer: PortableObjectsImporter?
    @ObservationIgnored private var locateStaging: () throws -> URL

    init(locateStaging: @escaping @Sendable () throws -> URL = DocumentsEverywhereSession.defaultStagingRoot) {
        self.locateStaging = locateStaging
    }

    var selected: Entry? {
        entries.first { $0.id == selectedID }
    }

    func open(library: LabLibrary) async {
        guard phase == .notStarted else { return }
        do {
            let root = try locateStaging()
            let backend = LibraryPortableBackend(library: library)
            importer = try PortableObjectsImporter(backend: backend, stagingRoot: root)
            let items = try await catalog.enumerate()
            entries = items.compactMap { item in
                guard let sample = catalog.sample(id: item.id) else { return nil }
                return Entry(item: item, sample: sample)
            }
            selectedID = entries.first?.id
            if let selectedID {
                preview = try DocumentPreviewBuilder.preview(sample: selectedID, from: catalog)
            }
            try await refreshDestinations(backend)
            phase = .ready
            providerState = .disabled
        } catch let error as DocumentsEverywhereError {
            phase = .unavailable(error.userMessage)
        } catch let error as PortableObjectError {
            phase = .unavailable(error.userMessage)
        } catch {
            phase = .unavailable("Documents Everywhere isn't ready.")
        }
    }

    func refresh(_ library: LabLibrary) async {
        let backend = LibraryPortableBackend(library: library)
        try? await refreshDestinations(backend)
    }

    private func refreshDestinations(_ backend: LibraryPortableBackend) async throws {
        let collections = try await backend.collections()
        destinations = collections.filter { $0.namespace == .user && !$0.isArchived }
            .sorted { $0.title.value.localizedStandardCompare($1.title.value) == .orderedAscending }
        if let chosen = destinationID, !destinations.contains(where: { $0.id == chosen }) {
            destinationID = nil
        }
        if destinationID == nil, destinations.count == 1 {
            destinationID = destinations[0].id
        }
    }

    func select(_ id: ProviderItemID) {
        selectedID = id
        outcome = nil
        do {
            let built = try DocumentPreviewBuilder.preview(sample: id, from: catalog)
            preview = built
            outcome = .previewed(built)
        } catch {
            preview = nil
            outcome = .refused(error.userMessage)
        }
    }

    /// Adopts the selected sample into the chosen collection through the Portable Objects importer.
    func adoptSelected() async {
        guard let selectedID, let importer, let destinationID else { return }
        outcome = nil
        do {
            let adopter = SampleAdopter(importer: importer, catalog: catalog)
            let result = try await adopter.adopt(selectedID, into: destinationID)
            outcome = .adopted(result)
        } catch {
            if error == .cancelled {
                outcome = .cancelled
            } else {
                outcome = .refused(error.userMessage)
            }
        }
    }

    /// Attempting to activate the provider in this build always reports disabled.
    func requestProviderActivation() -> DocumentsEverywhereError {
        .providerDisabled
    }

    nonisolated static func defaultStagingRoot() throws -> URL {
        try LabStoreLocation.defaultURL().deletingLastPathComponent()
            .appending(path: "Documents Everywhere Staging", directoryHint: .isDirectory)
    }
}
