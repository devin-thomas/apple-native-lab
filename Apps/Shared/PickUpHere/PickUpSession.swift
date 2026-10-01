import Foundation
import LabDomain
import Observation
import PickUpHere
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// LAB-016 in one window: the draft to continue, the hint being advertised, and what a hint
/// resolved to. Reads and the import commit go through `LibraryPickUpBackend`, so they are the
/// same authorized operation the tests call. Clearing a continuation drops that in-memory hint
/// and the text on screen. It does not delete a draft.
@MainActor
@Observable
final class PickUpSession {
    private(set) var items: [LabItem] = []
    var selectedItemID: ItemID?
    var selectedSection = 0
    private(set) var offer: ContinuationOffer?
    var isAdvertising = false
    private(set) var decision: ResumeDecision?
    var linkText = ""
    var documentText = ""
    private(set) var message: String?
    /// Drafts whose contents this window must not show. In memory only; it does not change the store.
    private(set) var revoked: Set<ItemID> = []
    private(set) var isWorking = false

    func load(_ library: LabLibrary) async {
        do {
            items = try await backend(library).items().sorted {
                $0.title.value.localizedStandardCompare($1.title.value) == .orderedAscending
            }
            if let selectedItemID, !items.contains(where: { $0.id == selectedItemID }) {
                self.selectedItemID = nil
            }
        } catch {
            message = error.sentence
        }
    }

    func item(_ id: ItemID?) -> LabItem? {
        id.flatMap { id in items.first { $0.id == id } }
    }

    func sections(of item: LabItem) -> [String] {
        DraftText.sections(in: item.note.value)
    }

    /// Builds the hint and the document after a permitted read. A revoked draft produces neither.
    func prepare(_ library: LabLibrary) async -> ContinuationOffer? {
        guard let item = item(selectedItemID) else {
            message = "Choose a draft first."
            return nil
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let offer = try await PickUpResolver(backend: backend(library)).prepare(item: item.id, section: selectedSection)
            self.offer = offer
            message = nil
            return offer
        } catch {
            offer = nil
            isAdvertising = false
            message = error.sentence
            if case .notAuthorized = error { decision = .accessRevoked(DocumentLocator(documentID: item.id, revision: item.revision)) }
            return nil
        }
    }

    func advertise(_ library: LabLibrary) async {
        guard await prepare(library) != nil else { return }
        isAdvertising = true
        message = "Handoff is advertised from this window. It carries the identifier and section, not the draft."
    }

    func copyLink(_ library: LabLibrary) async {
        guard let offer = await prepare(library) else { return }
        ContinuationClipboard.copy(offer.link.absoluteString)
        message = "Copied the continuation link. It has the identifier and section, not the draft."
    }

    func copyDocument(_ library: LabLibrary) async {
        guard let offer = await prepare(library) else { return }
        ContinuationClipboard.copy(offer.document.text)
        message = "Copied the continuation document. Import it on the other device. Handoff does not carry it."
    }

    func resumeLink(_ library: LabLibrary) async {
        guard let url = URL(string: linkText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            message = PickUpError.invalidPayload.sentence
            decision = nil
            return
        }
        await resume(url: url, library: library)
    }

    func accept(_ activity: NSUserActivity, library: LabLibrary) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let token = try HandoffActivity.token(from: activity)
            decision = try await PickUpResolver(backend: backend(library)).resume(token)
            message = decision?.sentence
            linkText = ContinuationLink.url(for: token).absoluteString
        } catch {
            decision = nil
            message = error.sentence
        }
    }

    func importPastedDocument(_ library: LabLibrary) async {
        guard let data = documentText.data(using: .utf8) else {
            message = PickUpError.invalidPayload.sentence
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let document = try ContinuationDocument(decoding: data)
            let collection = try await holdingCollection(in: library)
            let result = try await ContinuationImporter.importDocument(document, into: collection, backend: backend(library))
            await load(library)
            selectedItemID = result.itemID
            if result.receipt == nil {
                message = "This draft is already in the lab. Nothing was added."
            }
            if let url = URL(string: linkText.trimmingCharacters(in: .whitespacesAndNewlines)),
               (try? ContinuationLink.token(parsing: url)) != nil {
                await resume(url: url, library: library)
            } else {
                let position = try SectionPosition(section: 0)
                let token = ContinuationToken(
                    locator: DocumentLocator(documentID: document.documentID, revision: document.revision),
                    position: position
                )
                decision = try await PickUpResolver(backend: backend(library)).resume(token)
                message = decision?.sentence
            }
        } catch {
            message = error.sentence
        }
    }

    func addSample(_ library: LabLibrary) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let document = try SampleDraft.document()
            let collection = try await holdingCollection(in: library)
            _ = try await ContinuationImporter.importDocument(document, into: collection, backend: backend(library))
            await load(library)
            selectedItemID = SampleDraft.documentID
            selectedSection = SampleDraft.selectedSection
            message = "Added the sample draft. Choose Advertise, or copy the link or the document."
        } catch {
            message = error.sentence
        }
    }

    func revokeSelected() {
        guard let id = selectedItemID else { return }
        revoked.insert(id)
        if offer?.token.locator.documentID == id {
            offer = nil
            isAdvertising = false
        }
        decision = .accessRevoked(DocumentLocator(documentID: id, revision: item(id)?.revision ?? .initial))
        message = decision?.sentence
    }

    func allowSelected() {
        guard let id = selectedItemID else { return }
        revoked.remove(id)
        decision = nil
        message = "Access is allowed again. Continue to read the draft from this lab."
    }

    /// Drops the advertised activity, the pasted hint, and any text this window was showing.
    /// Drafts stored in the lab stay, including one the sample button added.
    func clear() {
        offer = nil
        isAdvertising = false
        decision = nil
        linkText = ""
        documentText = ""
        message = "Cleared the continuation. Drafts already in the lab were kept."
    }

    // MARK: Private

    private func backend(_ library: LabLibrary) -> LibraryPickUpBackend {
        LibraryPickUpBackend(library: library, revoked: revoked)
    }

    private func resume(url: URL, library: LabLibrary) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let token = try ContinuationLink.token(parsing: url)
            decision = try await PickUpResolver(backend: backend(library)).resume(token)
            message = decision?.sentence
        } catch {
            decision = nil
            message = error.sentence
        }
    }

    /// A collection of the person's own. When the lab has none, this creates one named Drafts.
    /// That collection is ordinary user data: Reset Demo does not remove it.
    private func holdingCollection(in library: LabLibrary) async throws(PickUpError) -> CollectionID {
        let found = try await backend(library).collections()
        let own = found.filter { $0.namespace == .user && !$0.isArchived }
        if let drafts = own.first(where: { $0.title.value == "Drafts" }) ?? own.first {
            return drafts.id
        }
        let id = SampleDraft.collectionID
        let title: EntityTitle
        do { title = try EntityTitle("Drafts") } catch { throw .unavailable }
        let draft = CollectionDraft(id: id, title: title)
        _ = try await backend(library).commit(
            .createCollection(draft: draft),
            requestID: RequestID(),
            names: [.collection(id): "Drafts"]
        )
        return id
    }
}

/// The host's adapter. Reads go through `LabDataService` as the app UI. The import commit goes
/// through `LabLibrary.submit`, so its receipt joins the session list. A revoked id is refused
/// before the item is read.
struct LibraryPickUpBackend: PickUpBackend {
    let library: LabLibrary
    let revoked: Set<ItemID>

    func access(to id: ItemID) async throws(PickUpError) -> DraftAccess {
        if revoked.contains(id) { return .revoked }
        let service = try await opened()
        do {
            _ = try await service.item(id, as: LabDataService.appUI)
            return .permitted
        } catch .unauthorized {
            return .revoked
        } catch .notFound {
            return .permitted
        } catch .storeFailure {
            throw .unavailable
        } catch {
            throw .unavailable
        }
    }

    func item(_ id: ItemID) async throws(PickUpError) -> LabItem? {
        let service = try await opened()
        do { return try await service.item(id, as: LabDataService.appUI) } catch .notFound { return nil } catch {
            throw PickUpError(error)
        }
    }

    func items() async throws(PickUpError) -> [LabItem] {
        let service = try await opened()
        let filter: ItemFilter
        do { filter = try ItemFilter(includeArchived: true, limit: ItemFilter.allowedLimits.upperBound) } catch {
            throw .unavailable
        }
        do { return try await service.items(filter, as: LabDataService.appUI) } catch { throw PickUpError(error) }
    }

    func collections() async throws(PickUpError) -> [LabCollection] {
        let service = try await opened()
        do { return try await service.collections(as: LabDataService.appUI) } catch { throw PickUpError(error) }
    }

    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(PickUpError) -> ActionReceipt {
        do {
            return try await library.submit(operation, requestID: requestID, authority: .userAction, names: names).receipt
        } catch {
            switch error {
            case .unavailable: throw .unavailable
            case .refused(let refusal): throw PickUpError(refusal)
            }
        }
    }

    private func opened() async throws(PickUpError) -> LabDataService {
        do { return try await library.openedService() } catch { throw .unavailable }
    }
}

enum ContinuationClipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}
