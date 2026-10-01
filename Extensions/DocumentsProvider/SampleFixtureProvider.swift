import DocumentsEverywhere
import FileProvider
import Foundation
import UniformTypeIdentifiers

/// Local-fixture File Provider for LAB-009. FrontierOptional only; never embedded in CoreLocal.
///
/// Serves the same bundled samples the document browser lists. The host does not call
/// `NSFileProviderManager.addDomain` in this build — the provider stays disabled until
/// LAB-009-B qualifies it. Disconnect and eviction are modeled in `ProviderSession` and covered
/// by package tests; this extension is the native adapter shell.
final class SampleFixtureProvider: NSObject, NSFileProviderReplicatedExtension {
    private let catalog = SampleCatalog.bundled
    private var session = ProviderSession()

    required init(domain: NSFileProviderDomain) {
        super.init()
        // Domain registration is the system's signal; the lab still treats the feature as
        // disabled until the host explicitly connects a session (LAB-009-B).
        _ = domain
    }

    func invalidate() {
        _ = session.disconnect()
    }

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> any NSFileProviderEnumerator {
        SampleFixtureEnumerator(catalog: catalog, container: containerItemIdentifier)
    }

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        if identifier == .rootContainer {
            progress.completedUnitCount = 1
            completionHandler(SampleFixtureItem.root, nil)
            return progress
        }
        let id = ProviderItemID(rawValue: identifier.rawValue)
        do {
            let items = try catalog.providerItems()
            guard let item = items.first(where: { $0.id == id }) else {
                progress.completedUnitCount = 1
                completionHandler(nil, NSFileProviderError(.noSuchItem))
                return progress
            }
            progress.completedUnitCount = 1
            completionHandler(SampleFixtureItem(item), nil)
        } catch {
            progress.completedUnitCount = 1
            completionHandler(nil, error)
        }
        return progress
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let id = ProviderItemID(rawValue: itemIdentifier.rawValue)
        do {
            let data = try catalog.data(for: id)
            let items = try catalog.providerItems()
            guard let item = items.first(where: { $0.id == id }) else {
                progress.completedUnitCount = 1
                completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
                return progress
            }
            let folder = FileManager.default.temporaryDirectory
                .appending(path: "DocumentsEverywhere-FP/\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: item.filename, directoryHint: .notDirectory)
            try data.write(to: url, options: [.atomic])
            progress.completedUnitCount = 1
            completionHandler(url, SampleFixtureItem(item), nil)
        } catch {
            progress.completedUnitCount = 1
            completionHandler(nil, nil, error)
        }
        return progress
    }

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        progress.completedUnitCount = 1
        // Read-only fixture provider: refuse creates. Authoritative samples stay in the catalog.
        completionHandler(nil, [], false, NSFileProviderError(.notAuthenticated))
        return progress
    }

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        progress.completedUnitCount = 1
        // External edits are tested in ProviderSession with DocumentRevision rules; this build
        // does not mutate fixtures through the live provider.
        completionHandler(nil, [], false, NSFileProviderError(.versionConflict))
        return progress
    }

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        progress.completedUnitCount = 1
        // Eviction of a mirror must not delete the authoritative catalog sample. Refuse.
        completionHandler(NSFileProviderError(.notAuthenticated))
        return progress
    }
}

/// One enumerator over the bundled sample fixtures.
final class SampleFixtureEnumerator: NSObject, NSFileProviderEnumerator {
    private let catalog: SampleCatalog
    private let container: NSFileProviderItemIdentifier

    init(catalog: SampleCatalog, container: NSFileProviderItemIdentifier) {
        self.catalog = catalog
        self.container = container
    }

    func invalidate() {}

    func enumerateItems(
        for observer: any NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        guard container == .rootContainer else {
            observer.finishEnumerating(upTo: nil)
            return
        }
        do {
            let items = try catalog.providerItems().map(SampleFixtureItem.init)
            observer.didEnumerate(items)
            observer.finishEnumerating(upTo: nil)
        } catch {
            observer.finishEnumeratingWithError(error)
        }
    }

    func enumerateChanges(
        for observer: any NSFileProviderChangeObserver,
        from syncAnchor: NSFileProviderSyncAnchor
    ) {
        observer.finishEnumeratingChanges(upTo: syncAnchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(NSFileProviderSyncAnchor(Data("documents-everywhere-v1".utf8)))
    }
}

/// Bridges a lab `ProviderItem` to `NSFileProviderItem`.
final class SampleFixtureItem: NSObject, NSFileProviderItem {
    let item: ProviderItem?

    static let root = SampleFixtureItem(root: true)

    private let isRoot: Bool

    init(_ item: ProviderItem) {
        self.item = item
        self.isRoot = false
    }

    private init(root: Bool) {
        self.item = nil
        self.isRoot = root
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        if isRoot { return .rootContainer }
        return NSFileProviderItemIdentifier(item!.id.rawValue)
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        if isRoot { return .rootContainer }
        return .rootContainer
    }

    var filename: String {
        if isRoot { return "Native Lab Samples" }
        return item!.filename
    }

    var contentType: UTType {
        if isRoot { return .folder }
        return UTType(item!.contentTypeIdentifier) ?? .json
    }

    var documentSize: NSNumber? {
        item?.byteCount.map { NSNumber(value: $0) }
    }

    var itemVersion: NSFileProviderItemVersion {
        guard let revision = item?.revision else {
            return NSFileProviderItemVersion()
        }
        return NSFileProviderItemVersion(
            contentVersion: revision.contentVersionData,
            metadataVersion: revision.metadataVersionData
        )
    }

    var capabilities: NSFileProviderItemCapabilities {
        if isRoot { return [.allowsContentEnumerating, .allowsReading] }
        return [.allowsReading]
    }
}
