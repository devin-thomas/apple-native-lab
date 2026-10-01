import Foundation
import LabDomain
import Testing
@testable import PickUpHere

@Suite struct ResumeTests {
    private let resolverID = ItemID(rawValue: UUID(uuidString: "01600000-0000-4000-8000-0000000000AA")!)

    @Test func aMissingDocumentPromptsImportInsteadOfSucceeding() async throws {
        let lab = try await PickUpLab.make()
        let token = ContinuationToken(
            locator: DocumentLocator(documentID: resolverID, revision: .initial),
            position: try SectionPosition(section: 1)
        )
        let decision = try await PickUpResolver(backend: lab.backend).resume(token)
        #expect(decision.resumed == nil)
        guard case .needsImport(let locator) = decision else {
            Issue.record("Expected an import prompt, got \(decision)")
            return
        }
        #expect(locator == token.locator)
        #expect(decision.revealedText.isEmpty)
        #expect(decision.sentence.contains("Import the document"))
        #expect(!decision.sentence.contains("Resumed"))
        #expect(await lab.itemCount() == 0)
    }

    @Test func revokedAccessDoesNotReadOrRevealTheDraft() async throws {
        let id = resolverID
        let lab = try await PickUpLab.make(revoked: { $0 == id })
        let item = try await lab.addItem(id: resolverID, title: "Hidden title", note: Sentinel.note)
        let offer = try await PickUpResolver(backend: ServicePickUpBackend(service: lab.service, actor: lab.actor))
            .prepare(item: item.id, section: 1)
        #expect(offer.document.sections[1] == Sentinel.text)

        let decision = try await PickUpResolver(backend: lab.backend).resume(offer.token)
        guard case .accessRevoked = decision else {
            Issue.record("Expected revocation, got \(decision)")
            return
        }
        #expect(decision.revealedText.isEmpty)
        #expect(!decision.sentence.contains(Sentinel.text))
        #expect(!decision.sentence.contains("Hidden title"))
        #expect(!decision.revealedText.contains(Sentinel.text))
    }

    @Test func anActorWithoutReadPermissionRevealsNothing() async throws {
        let lab = try await PickUpLab.make()
        let item = try await lab.addItem(id: resolverID, title: "Hidden title", note: Sentinel.note)
        let reader = ServicePickUpBackend(service: lab.service, actor: lab.actor)
        let offer = try await PickUpResolver(backend: reader).prepare(item: item.id, section: 1)
        let denied = ActorScope(adapter: .appUI, grants: [])
        let decision = try await PickUpResolver(backend: ServicePickUpBackend(service: lab.service, actor: denied))
            .resume(offer.token)
        guard case .accessRevoked = decision else {
            Issue.record("Expected revocation, got \(decision)")
            return
        }
        #expect(decision.revealedText.isEmpty)
        #expect(!decision.sentence.contains(Sentinel.text))
    }

    @Test func preparingARevokedDraftReturnsNoDocument() async throws {
        let lab = try await PickUpLab.make(revoked: { _ in true })
        let item = try await lab.addItem(id: resolverID, title: "Hidden title", note: Sentinel.note)
        await #expect(throws: PickUpError.notAuthorized) {
            try await PickUpResolver(backend: lab.backend).prepare(item: item.id, section: 1)
        }
    }

    @Test func aShorterNewerDraftClampsTheSavedPosition() async throws {
        let lab = try await PickUpLab.make()
        let item = try await lab.addItem(id: resolverID, title: "Workbench", note: Sentinel.note)
        let offer = try await PickUpResolver(backend: lab.backend).prepare(item: item.id, section: 1)
        #expect(offer.token.position.section == 1)
        let shortened = try ItemNote("Only the opening remains.")
        _ = try await lab.service.perform(OperationRequest(
            id: RequestID(),
            operation: .updateItem(id: item.id, expected: item.revision, changes: try ItemChanges(note: shortened)),
            actor: lab.actor
        ))
        let decision = try await PickUpResolver(backend: lab.backend).resume(offer.token)
        guard let resumed = decision.resumed else {
            Issue.record("Expected a resumed draft")
            return
        }
        #expect(resumed.newerRevision)
        #expect(resumed.clamped)
        #expect(resumed.requestedSection == 1)
        #expect(resumed.section == 0)
        #expect(resumed.sectionText == "Only the opening remains.")
        #expect(!resumed.sections.contains(Sentinel.text))
        #expect(resumed.revision > offer.token.locator.revision)
    }

    @Test func aNewerDraftKeepsAPositionThatStillExists() async throws {
        let lab = try await PickUpLab.make()
        let item = try await lab.addItem(id: resolverID, title: "Workbench", note: Sentinel.note)
        let offer = try await PickUpResolver(backend: lab.backend).prepare(item: item.id, section: 1)
        _ = try await lab.service.perform(OperationRequest(
            id: RequestID(),
            operation: .updateItem(id: item.id, expected: item.revision, changes: try ItemChanges(title: try EntityTitle("Workbench renamed"))),
            actor: lab.actor
        ))
        let decision = try await PickUpResolver(backend: lab.backend).resume(offer.token)
        guard let resumed = decision.resumed else {
            Issue.record("Expected a resumed draft")
            return
        }
        #expect(resumed.newerRevision)
        #expect(!resumed.clamped)
        #expect(resumed.section == 1)
        #expect(resumed.sectionText == Sentinel.text)
        #expect(resumed.title == "Workbench renamed")
    }

    @Test func anUnchangedDraftResumesAtTheSelectedSection() async throws {
        let lab = try await PickUpLab.make()
        let item = try await lab.addItem(id: resolverID, title: "Workbench", note: Sentinel.note)
        let offer = try await PickUpResolver(backend: lab.backend).prepare(item: item.id, section: 1)
        let decision = try await PickUpResolver(backend: lab.backend).resume(offer.token)
        guard let resumed = decision.resumed else {
            Issue.record("Expected a resumed draft")
            return
        }
        #expect(!resumed.clamped)
        #expect(!resumed.newerRevision)
        #expect(resumed.sectionText == Sentinel.text)
        #expect(resumed.revision == item.revision)
    }

    @Test func cancellationReadsNothing() async throws {
        let gate = GateBackend(access: .permitted)
        let token = ContinuationToken(
            locator: DocumentLocator(documentID: resolverID, revision: .initial),
            position: try SectionPosition(section: 0)
        )
        let task = Task {
            try await PickUpResolver(backend: gate).resume(token)
        }
        task.cancel()
        let outcome = await task.result
        guard case .failure(let error) = outcome else {
            Issue.record("Expected cancellation")
            return
        }
        #expect(error as? PickUpError == .cancelled)
        #expect(gate.itemReads == 0)
    }

    @Test func aNegativeSectionIsRefused() {
        #expect(throws: PickUpError.invalidPayload) { try SectionPosition(section: -1) }
    }

    @Test func anUnavailableStoreDoesNotResume() async throws {
        let backend = UnavailableBackend()
        let token = ContinuationToken(
            locator: DocumentLocator(documentID: resolverID, revision: .initial),
            position: try SectionPosition(section: 0)
        )
        await #expect(throws: PickUpError.unavailable) {
            try await PickUpResolver(backend: backend).resume(token)
        }
    }
}

private struct UnavailableBackend: PickUpBackend {
    func access(to id: ItemID) async throws(PickUpError) -> DraftAccess { throw .unavailable }
    func item(_ id: ItemID) async throws(PickUpError) -> LabItem? { throw .unavailable }
    func items() async throws(PickUpError) -> [LabItem] { throw .unavailable }
    func collections() async throws(PickUpError) -> [LabCollection] { [] }
    func commit(
        _ operation: DomainOperation,
        requestID: RequestID,
        names: [EntityReference: String]
    ) async throws(PickUpError) -> ActionReceipt { throw .unavailable }
}
