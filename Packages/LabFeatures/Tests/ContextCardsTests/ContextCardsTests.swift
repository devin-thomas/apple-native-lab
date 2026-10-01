import ActionAtlas
import ContextCards
import Foundation
import LabDomain
import Testing

@Suite struct ContextCardsSchemaTests {
    @Test func aLabSampleMatchesNoInstalledSchema() {
        let entities = ["NoteEntity", "BookEntity", "MailMessageEntity", "PhotoEntity", "FileEntity"]
        for domain in SchemaGate.installedDomains {
            for entity in entities {
                let decision = SchemaGate.decide(.labSample, claim: SchemaClaim(domain: domain, entity: entity))
                guard case .mismatch(let reason) = decision else {
                    Issue.record("\(domain).\(entity) was adopted")
                    continue
                }
                #expect(reason.contains("integration gate failed"))
                #expect(reason.contains("Nothing was associated"))
            }
        }
    }

    @Test func anUnknownSchemaAlsoFailsTheGate() {
        let decision = SchemaGate.decide(.labSample, claim: SchemaClaim(domain: "labSample", entity: "Swatch"))
        guard case .mismatch(let reason) = decision else {
            Issue.record("an invented schema was adopted")
            return
        }
        #expect(reason.contains("not an Apple schema"))
    }

    @Test func aBlankClaimFailsTheGate() {
        let decision = SchemaGate.decide(.labSample, claim: SchemaClaim(domain: "  ", entity: "NoteEntity"))
        guard case .mismatch(let reason) = decision else {
            Issue.record("a blank schema was adopted")
            return
        }
        #expect(reason.contains("domain and an entity"))
    }

    @Test func aMismatchedClaimDoesNotReplaceTheSampleOnScreen() throws {
        var board = ContextBoard()
        try board.show(sample(CardSeed.amber, title: "Amber swatch"))
        let kept = board.context
        let cobalt = try sample(CardSeed.cobalt, title: "Cobalt swatch")
        #expect(throws: ContextCardsError.self) {
            try board.show(cobalt, claiming: SchemaClaim(domain: "notes", entity: "NoteEntity"))
        }
        #expect(board.context == kept)
        #expect(board.context?.itemID == CardSeed.amber)
        #expect(board.context?.resolution == .unavailable)
    }

    @Test func associatingWithoutASchemaPublishesTheSampleAndSaysResolutionIsUnavailable() throws {
        let context = try VisibleEntityContext.make(item: try sample(CardSeed.amber, title: "Amber swatch"), claiming: nil, generation: 1)
        #expect(context.itemID == CardSeed.amber)
        #expect(context.generation == 1)
        #expect(context.resolution.sentence == "Context resolution is unavailable.")
    }
}

@Suite struct ContextCardsOperationTests {
    @Test(arguments: AtlasEntryPoint.allCases)
    func setAsideArchivesTheSampleOnScreenAndRecordsAReceipt(entryPoint: AtlasEntryPoint) async throws {
        let backend = try await CardBackend.seeded()
        let link = backend.link
        let actions = link.actions(entryPoint)
        let amber = try await actions.read(CardSeed.amber)
        let context = try VisibleEntityContext.make(item: amber, claiming: nil, generation: 1)
        link.publish(context)
        let spy = CardConfirmation()

        let outcome = try await actions.setAside(DecisionProposal(context), request: cardRequest(1), confirm: spy.approve)

        #expect(spy.count == 1)
        #expect(outcome.entity.isArchived)
        #expect(outcome.entity.id == CardSeed.amber)
        #expect(outcome.receipt.admitted.adapter == entryPoint.adapter)
        #expect(outcome.receipt.undo != nil)
        let cobalt = try await actions.read(CardSeed.cobalt)
        #expect(!cobalt.isArchived)
        #expect(backend.commitCount == 1)
    }

    @Test func aReplacedSampleCannotChangeThePreviousOne() async throws {
        let backend = try await CardBackend.seeded()
        let link = backend.link
        let actions = link.actions(.appUI)
        let amber = try await actions.read(CardSeed.amber)
        let cobalt = try await actions.read(CardSeed.cobalt)
        var board = ContextBoard()
        try board.show(amber)
        board.prepareDecision()
        let proposal = try #require(board.proposal)
        link.publish(board.context)
        try board.show(cobalt)
        link.publish(board.context)
        #expect(board.decisionIsStale)
        let spy = CardConfirmation()

        let error = await #expect(throws: ContextCardsError.self) {
            try await actions.setAside(proposal, request: cardRequest(1), confirm: spy.approve)
        }
        guard case .staleVisibleContent(let title)? = error else {
            Issue.record("expected a stale screen, got \(String(describing: error))")
            return
        }
        #expect(title == "Amber swatch")
        #expect(spy.count == 0)
        #expect(backend.commitCount == 0)
        #expect(try await actions.read(CardSeed.amber).isArchived == false)
        #expect(try await actions.read(CardSeed.cobalt).isArchived == false)
    }

    @Test func replacingTheSampleDuringConfirmationDoesNotChangeIt() async throws {
        let backend = try await CardBackend.seeded()
        let link = backend.link
        let actions = link.actions(.appIntent)
        let amber = try await actions.read(CardSeed.amber)
        let cobalt = try await actions.read(CardSeed.cobalt)
        let context = try VisibleEntityContext.make(item: amber, claiming: nil, generation: 1)
        link.publish(context)
        let replacement = try VisibleEntityContext.make(item: cobalt, claiming: nil, generation: 2)

        let error = await #expect(throws: ContextCardsError.self) {
            try await actions.setAside(DecisionProposal(context), request: cardRequest(1)) { _ in
                link.publish(replacement)
            }
        }
        guard case .staleVisibleContent? = error else {
            Issue.record("expected a stale screen, got \(String(describing: error))")
            return
        }
        #expect(backend.commitCount == 0)
        #expect(try await actions.read(CardSeed.amber).isArchived == false)
    }

    @Test func anExplicitShortcutSetsAsideTheNamedSampleWhileContextResolutionStaysUnavailable() async throws {
        let backend = try await CardBackend.seeded()
        let link = backend.link
        let actions = link.actions(.appIntent)
        let cobalt = try await actions.read(CardSeed.cobalt)
        link.publish(try VisibleEntityContext.make(item: cobalt, claiming: nil, generation: 4))
        let amber = try await actions.read(CardSeed.amber)
        let entity = try await actions.entity(for: amber)
        let intent = SetAsideSampleIntent(item: entity, seenGeneration: nil)
        intent.requestID = cardRequest(2).id.rawValue.uuidString
        let spy = CardConfirmation()

        let outcome = try await intent.run(with: link, confirm: spy.approve)

        #expect(spy.count == 1)
        #expect(outcome.entity.isArchived)
        #expect(outcome.dialog.contains("Context resolution is unavailable."))
        #expect(try await actions.read(CardSeed.cobalt).isArchived == false)
    }

    @Test func repeatingARequestSetsAsideOnce() async throws {
        let backend = try await CardBackend.seeded()
        let link = backend.link
        let actions = link.actions(.appUI)
        let amber = try await actions.read(CardSeed.amber)
        let context = try VisibleEntityContext.make(item: amber, claiming: nil, generation: 1)
        link.publish(context)
        let spy = CardConfirmation()
        let first = try await actions.setAside(DecisionProposal(context), request: cardRequest(3), confirm: spy.approve)
        let second = try await actions.setAside(DecisionProposal(context), request: cardRequest(3), confirm: spy.approve)
        #expect(first.receipt.operationID == second.receipt.operationID)
        #expect(try await actions.read(CardSeed.amber).revision == first.entity.revision)
    }

    @Test func cancellingBeforeTheCommitChangesNothing() async throws {
        let backend = try await CardBackend.seeded()
        let link = backend.link
        let actions = link.actions(.appIntent)
        let amber = try await actions.read(CardSeed.amber)
        link.publish(try VisibleEntityContext.make(item: amber, claiming: nil, generation: 1))
        let spy = CardConfirmation()
        let error = await #expect(throws: ContextCardsError.self) {
            try await actions.setAside(DecisionProposal(link.visible!), request: cardRequest(4), confirm: spy.decline)
        }
        guard case .cancelled? = error else {
            Issue.record("expected cancellation, got \(String(describing: error))")
            return
        }
        #expect(spy.count == 1)
        #expect(backend.commitCount == 0)
        #expect(try await actions.read(CardSeed.amber).isArchived == false)
    }

    @Test func aMissingSampleAndABadRequestIDChangeNothing() async throws {
        let backend = try await CardBackend.seeded()
        let link = backend.link
        let missing = ItemID(rawValue: UUID(uuidString: "00000000-0002-4000-8000-000000000099")!)
        let proposal = DecisionProposal(itemID: missing, revision: .initial, generation: nil, title: "Missing")
        let spy = CardConfirmation()
        let missingError = await #expect(throws: ContextCardsError.self) {
            try await link.actions(.appUI).setAside(proposal, request: cardRequest(5), confirm: spy.approve)
        }
        guard case .action(.missingItem)? = missingError else {
            Issue.record("expected a missing sample, got \(String(describing: missingError))")
            return
        }
        #expect(spy.count == 0)
        #expect(backend.commitCount == 0)

        let amber = try await link.actions(.appIntent).read(CardSeed.amber)
        let entity = try await link.actions(.appIntent).entity(for: amber)
        let intent = SetAsideSampleIntent(item: entity, seenGeneration: nil)
        intent.requestID = "not-a-uuid"
        let invalid = await #expect(throws: ContextCardsError.self) {
            try await intent.run(with: link, confirm: spy.approve)
        }
        guard case .invalidRequestID? = invalid else {
            Issue.record("expected a bad request ID, got \(String(describing: invalid))")
            return
        }
        #expect(backend.commitCount == 0)
    }

    @Test func withoutAStoreTheDecisionSaysTheLabIsUnavailable() async throws {
        let link = ContextCardsLink.unavailable
        let proposal = DecisionProposal(itemID: CardSeed.amber, revision: .initial, generation: nil, title: "Amber swatch")
        let spy = CardConfirmation()
        let error = await #expect(throws: ContextCardsError.self) {
            try await link.actions(.appIntent).setAside(proposal, request: cardRequest(6), confirm: spy.approve)
        }
        guard case .action(.unavailable(let reason))? = error else {
            Issue.record("expected the unavailable path, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("has not opened its store"))
        #expect(spy.count == 0)
    }
}

@Suite struct ContextCardsSurfaceTests {
    @Test func aSiriDisabledDeviceKeepsTheSameDecisionCard() {
        let enabled = DecisionCard.showing(title: "Amber swatch", note: "Warm yellow-brown.", siriEnabled: true)
        let disabled = DecisionCard.showing(title: "Amber swatch", note: "Warm yellow-brown.", siriEnabled: false)
        #expect(enabled == disabled)
        #expect(disabled.acceptLabel == "Set Aside")
        #expect(disabled.cancelLabel == "Cancel")
        #expect(disabled.prompt.contains("Amber swatch"))
        #expect(disabled.contextResolution == "Context resolution is unavailable.")
    }

    @Test func askingReadsTheSampleAndDoesNotChangeIt() async throws {
        let backend = try await CardBackend.seeded()
        let link = backend.link
        let amber = try await link.actions(.appIntent).read(CardSeed.amber)
        let entity = try await link.actions(.appIntent).entity(for: amber)
        let intent = AskAboutVisibleSampleIntent()
        intent.item = entity
        link.publish(try VisibleEntityContext.make(item: amber, claiming: nil, generation: 2))

        let outcome = try await intent.run(with: link)

        #expect(outcome.dialog.contains("Amber swatch"))
        #expect(outcome.dialog.contains("Context resolution is unavailable."))
        #expect(outcome.card == DecisionCard.showing(title: "Amber swatch", note: "Warm yellow-brown.", siriEnabled: false))
        #expect(outcome.seenGeneration == 2)
        #expect(backend.commitCount == 0)
        #expect(try await link.actions(.appIntent).read(CardSeed.amber).isArchived == false)
    }

    @Test func replacingTheSampleDonatesADifferentEntityIdentifier() {
        let amber = VisibleSampleActivity.identifier(for: CardSeed.amber.rawValue)
        let cobalt = VisibleSampleActivity.identifier(for: CardSeed.cobalt.rawValue)
        #expect(amber != cobalt)
        let activity = NSUserActivity(activityType: "org.example.nativelab.context-cards.visible-sample")
        VisibleSampleActivity.fill(activity, title: "Cobalt swatch", itemID: CardSeed.cobalt.rawValue)
        #expect(activity.title == "Cobalt swatch")
        #expect(activity.appEntityIdentifier == cobalt)
        #expect(activity.isEligibleForHandoff == false)
    }
}

private func sample(_ id: ItemID, title: String) throws -> LabItem {
    try LabItem(id: id, collectionID: CardSeed.pigments, title: EntityTitle(title), namespace: .demo)
}
