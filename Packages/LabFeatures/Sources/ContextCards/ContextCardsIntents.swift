import ActionAtlas
import AppIntents
import Foundation
import LabDomain
import SwiftUI

/// What Ask About Visible Sample returns besides the entity: the sentence, the card, and the
/// screen generation the snippet's button should bind to, if the named sample is the one on screen.
public struct AskOutcome: Sendable {
    public let entity: LabItemEntity
    public let dialog: String
    public let card: DecisionCard
    public let seenGeneration: Int?
}

/// What an intent returns after a set-aside: the entity and the sentence, which includes the
/// receipt and the unavailable context resolution.
public struct SetAsideOutcome: Sendable {
    public let entity: LabItemEntity
    public let dialog: String
    public let receipt: ActionReceipt
}

// Both intents are thin adapters. `perform()` adds the system's dialog, snippet, or confirmation.
// `run(with:)` does the work and is what the tests call. Each requires an unlocked device, because
// the lab may hold the person's own samples. Neither is a curated App Shortcut: Siri phrasing and
// region are a separate gate, and the actions stay in the typed Shortcut library.

public struct AskAboutVisibleSampleIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ask About Visible Sample"
    public static let description = IntentDescription(
        "Reads one lab sample and shows it on a card. Context resolution is unavailable, so the sample is the one you name."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Sample")
    public var item: LabItemEntity

    @Dependency(default: ContextCardsLink.unavailable) private var cards: ContextCardsLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Ask about \(\.$item)")
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<LabItemEntity> & ProvidesDialog & ShowsSnippetView {
        let output = try await run(with: cards)
        let confirm = SetAsideSampleIntent(item: output.entity, seenGeneration: output.seenGeneration)
        return .result(value: output.entity, dialog: "\(output.dialog)") {
            DecisionSnippetView(card: output.card, confirm: confirm)
        }
    }

    /// The intent's work without the system. The sample is read again, and the sentence says
    /// context resolution is unavailable.
    public func run(with link: ContextCardsLink) async throws(ContextCardsError) -> AskOutcome {
        let actions = link.actions(.appIntent)
        let current = try await actions.read(item.itemID)
        let entity = try await actions.entity(for: current)
        let card = DecisionCard.showing(title: entity.title, note: entity.note, siriEnabled: false)
        let generation = link.visible.flatMap { visible in visible.itemID == current.id ? visible.generation : nil }
        return AskOutcome(
            entity: entity,
            dialog: ContextCards.askDialog(title: entity.title, note: entity.note),
            card: card,
            seenGeneration: generation
        )
    }
}

public struct SetAsideSampleIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Aside Visible Sample"
    public static let description = IntentDescription(
        "Sets a lab sample aside after you confirm. Nothing is deleted, and the receipt in Native Lab offers an undo. Reset Demo restores a demo sample."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Sample")
    public var item: LabItemEntity

    @Parameter(
        title: "Seen Generation",
        description: "Optional. The card's generation when this decision was made. If another sample is on screen, nothing is changed."
    )
    public var seenGeneration: Int?

    @Parameter(
        title: "Request ID",
        description: "Optional. Running again with the same request ID returns the first result instead of setting the sample aside again."
    )
    public var requestID: String?

    @Dependency(default: ContextCardsLink.unavailable) private var cards: ContextCardsLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Set aside \(\.$item)") {
            \.$seenGeneration
            \.$requestID
        }
    }

    public init() {}

    public init(item: LabItemEntity, seenGeneration: Int?) {
        self.item = item
        self.seenGeneration = seenGeneration
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<LabItemEntity> & ProvidesDialog {
        let promptCard = DecisionCard.showing(title: item.title, note: item.note, siriEnabled: false)
        let output = try await run(with: cards) { prompt in
            try await requestConfirmation(
                actionName: .custom(
                    acceptLabel: "Set Aside", acceptAlternatives: [],
                    denyLabel: "Cancel", denyAlternatives: [],
                    destructive: true
                ),
                dialog: "\(prompt.text)",
                content: { DecisionSnippetView(card: promptCard) }
            )
        }
        return .result(value: output.entity, dialog: "\(output.dialog)")
    }

    /// The intent's work without the system. `confirm` stands in for the system's confirmation.
    public func run(
        with link: ContextCardsLink,
        confirm: @Sendable (ArchivePrompt) async throws -> Void
    ) async throws -> SetAsideOutcome {
        guard let revision = Revision(rawValue: item.revision) else { throw ContextCardsError.action(.missingItem(item.itemID)) }
        let request: AtlasRequest
        do {
            request = try AtlasRequest(text: requestID)
        } catch {
            switch error {
            case .invalidRequestID: throw ContextCardsError.invalidRequestID
            default: throw ContextCardsError.action(error)
            }
        }
        let proposal = DecisionProposal(
            itemID: item.itemID, revision: revision, generation: seenGeneration, title: item.title
        )
        let actions = link.actions(.appIntent)
        let outcome = try await actions.setAside(proposal, request: request, confirm: confirm)
        let entity = try await actions.entity(for: outcome.entity)
        return SetAsideOutcome(
            entity: entity,
            dialog: ContextCards.completedDialog(summary: outcome.receipt.summary),
            receipt: outcome.receipt
        )
    }
}

/// Lets a host app include these intents in its App Intents metadata.
public struct ContextCardsIntentsPackage: AppIntentsPackage {}
