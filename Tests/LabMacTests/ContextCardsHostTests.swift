import ActionAtlas
import ContextCards
import Foundation
import LabDomain
import Testing
@testable import NativeLab

/// LAB-002 in the sandboxed Mac host: the activity type, the sidebar destination, and set-aside
/// through the same library Action Atlas uses. Each test uses a fresh SQLite store, never the
/// app's own. The system's snippet and confirmation dialog are not presented here.
@MainActor
@Suite struct ContextCardsHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ContextCardsHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func startedLibrary(_ name: String) async throws -> LabLibrary {
        let directory = folder.appending(path: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let library = LabLibrary(locateStore: { directory.appending(path: LabStoreLocation.fileName) })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    private func link(for library: LabLibrary) -> ContextCardsLink {
        ContextCardsLink(atlas: ActionAtlasLink(backend: LibraryAtlasBackend(library: library)))
    }

    @Test func theAppDeclaresTheContextCardsActivityTypeFromItsBundlePrefix() throws {
        let declared = try #require(Bundle.main.object(forInfoDictionaryKey: ContextCards.activityTypeInfoKey) as? String)
        let prefix = try #require(Bundle.main.bundleIdentifier?.split(separator: ".").dropLast().joined(separator: "."))
        #expect(declared == "\(prefix).nativelab.context-cards.visible-sample")
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") as? [String])
        #expect(types.contains(declared))
        #expect(ContextCardsSession.activityType == declared)
    }

    @Test func contextCardsIsASidebarDestinationWithCommandNine() {
        #expect(SidebarDestination(storageKey: SidebarDestination.contextCards.storageKey) == .contextCards)
        #expect(SidebarDestination.contextCards.title == ContextCards.title)
    }

    @Test func setAsideThroughTheHostLibraryArchivesOnlyTheSampleOnScreen() async throws {
        let library = try await startedLibrary("set-aside")
        let cards = link(for: library)
        let actions = cards.actions(.appUI)
        let amber = try await actions.read(ContextCards.primarySampleID)
        let context = try VisibleEntityContext.make(item: amber, claiming: nil, generation: 1)
        cards.publish(context)
        let request = AtlasRequest(RequestID(rawValue: UUID(uuidString: "00000000-0002-4000-8000-000000000101")!))

        let outcome = try await actions.setAside(DecisionProposal(context), request: request, confirm: { _ in })

        #expect(outcome.entity.isArchived)
        #expect(outcome.entity.id == ContextCards.primarySampleID)
        #expect(outcome.receipt.admitted.adapter == .appUI)
        #expect(outcome.receipt.undo != nil)
        #expect(library.receipt(id: outcome.receipt.operationID)?.receipt.admitted.adapter == .appUI)
        #expect(try await actions.read(ContextCards.replacementSampleID).isArchived == false)
    }

    @Test func aReplacedOnscreenSampleCannotMutateThePreviousOneThroughTheHost() async throws {
        let library = try await startedLibrary("stale")
        let cards = link(for: library)
        let actions = cards.actions(.appUI)
        let amber = try await actions.read(ContextCards.primarySampleID)
        let cobalt = try await actions.read(ContextCards.replacementSampleID)
        var board = ContextBoard()
        try board.show(amber)
        board.prepareDecision()
        let proposal = try #require(board.proposal)
        cards.publish(board.context)
        try board.show(cobalt)
        cards.publish(board.context)
        #expect(board.decisionIsStale)
        let before = library.receipts.count
        let request = AtlasRequest(RequestID(rawValue: UUID(uuidString: "00000000-0002-4000-8000-000000000102")!))

        let error = await #expect(throws: ContextCardsError.self) {
            try await actions.setAside(proposal, request: request, confirm: { _ in })
        }
        guard case .staleVisibleContent(let title)? = error else {
            Issue.record("expected a stale screen, got \(String(describing: error))")
            return
        }
        #expect(title == "Amber swatch")
        #expect(library.receipts.count == before)
        #expect(try await actions.read(ContextCards.primarySampleID).isArchived == false)
        #expect(try await actions.read(ContextCards.replacementSampleID).isArchived == false)
    }

    @Test func askingAboutASampleLeavesItUnchangedAndSaysResolutionIsUnavailable() async throws {
        let library = try await startedLibrary("ask")
        let cards = link(for: library)
        let actions = cards.actions(.appIntent)
        let amber = try await actions.read(ContextCards.primarySampleID)
        let entity = try await actions.entity(for: amber)
        cards.publish(try VisibleEntityContext.make(item: amber, claiming: nil, generation: 3))
        let intent = AskAboutVisibleSampleIntent()
        intent.item = entity

        let outcome = try await intent.run(with: cards)

        #expect(outcome.dialog.contains("Context resolution is unavailable."))
        #expect(outcome.seenGeneration == 3)
        #expect(outcome.card.acceptLabel == "Set Aside")
        #expect(outcome.card.cancelLabel == "Cancel")
        #expect(try await actions.read(ContextCards.primarySampleID).isArchived == false)
        // First-run seed only: Ask does not commit.
        #expect(library.receipts.count == 1)
        #expect(library.receipts.first?.receipt.admitted.operation.kind == .resetDemo)
    }
}
