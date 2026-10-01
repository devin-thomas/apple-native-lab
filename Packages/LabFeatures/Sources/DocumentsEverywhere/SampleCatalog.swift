import Foundation
import PortableObjects
import UniformTypeIdentifiers

/// One tiny, original sample document shipped with Documents Everywhere.
public struct SampleDocument: Hashable, Sendable, Identifiable {
    public let id: ProviderItemID
    public let filename: String
    public let displayName: String
    /// Resource name inside the module bundle (no extension).
    public let resourceName: String
    public let contentTypeIdentifier: String

    public init(
        id: ProviderItemID,
        filename: String,
        displayName: String,
        resourceName: String,
        contentTypeIdentifier: String = LabObjectType.defaultIdentifier
    ) {
        self.id = id
        self.filename = filename
        self.displayName = displayName
        self.resourceName = resourceName
        self.contentTypeIdentifier = contentTypeIdentifier
    }
}

/// The fixed catalog of safe sample documents. No remote storage; no production cloud.
public struct SampleCatalog: Sendable {
    public let samples: [SampleDocument]
    private let resourceBundle: Bundle

    public static let bundled = SampleCatalog(samples: SampleCatalog.fixtureList, resourceBundle: .module)

    public init(samples: [SampleDocument], resourceBundle: Bundle) {
        self.samples = samples
        self.resourceBundle = resourceBundle
    }

    /// Provider items for the root of the sample tree (files only; no folders in v1).
    public func providerItems() throws(DocumentsEverywhereError) -> [ProviderItem] {
        var items: [ProviderItem] = []
        items.reserveCapacity(samples.count)
        for sample in samples {
            let data = try data(for: sample.id)
            let revision: DocumentRevision
            if let document = try? LabDocument(decoding: data), let value = document.revision {
                revision = DocumentRevision(documentRevision: value)
            } else {
                revision = .initial
            }
            items.append(
                ProviderItem(
                    id: sample.id,
                    parentID: .root,
                    filename: sample.filename,
                    contentTypeIdentifier: sample.contentTypeIdentifier,
                    revision: revision,
                    isDirectory: false,
                    byteCount: data.count,
                    isMirror: false
                )
            )
        }
        return items
    }

    public func sample(id: ProviderItemID) -> SampleDocument? {
        samples.first { $0.id == id }
    }

    public func data(for id: ProviderItemID) throws(DocumentsEverywhereError) -> Data {
        guard let sample = sample(id: id) else { throw .unknownSample }
        guard let url = resourceBundle.url(forResource: sample.resourceName, withExtension: "anlab") else {
            throw .unavailable
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw .unavailable
        }
    }

    /// Enumerates samples, stopping if the task is cancelled.
    public func enumerate() async throws(DocumentsEverywhereError) -> [ProviderItem] {
        if Task.isCancelled { throw .cancelled }
        let items = try providerItems()
        if Task.isCancelled { throw .cancelled }
        return items
    }

    /// Opens one sample: returns its bytes and preview. Cancelled work leaves nothing behind.
    public func open(_ id: ProviderItemID) async throws(DocumentsEverywhereError) -> (data: Data, preview: DocumentPreview) {
        if Task.isCancelled { throw .cancelled }
        let data = try data(for: id)
        if Task.isCancelled { throw .cancelled }
        let preview = try DocumentPreviewBuilder.preview(of: data)
        if Task.isCancelled { throw .cancelled }
        return (data, preview)
    }

    /// The two original fixtures: short, public-safe, and unrelated to any personal document.
    public static let fixtureList: [SampleDocument] = [
        SampleDocument(
            id: ProviderItemID(rawValue: "sample.harbor-note"),
            filename: "harbor-note.anlab",
            displayName: "Harbor note",
            resourceName: "harbor-note"
        ),
        SampleDocument(
            id: ProviderItemID(rawValue: "sample.tide-card"),
            filename: "tide-card.anlab",
            displayName: "Tide card",
            resourceName: "tide-card"
        ),
    ]
}
