import Foundation
import LabDomain

/// How the system resolved the sample on screen. A lab sample has no matching schema, so this
/// build has only the unavailable reading.
public enum ContextResolution: Hashable, Sendable {
    case unavailable

    public var sentence: String { ContextCards.resolutionUnavailable }
}

/// The one sample associated with the card, at one generation.
///
/// Replacing the sample makes a new value with the next generation. A decision captured against
/// an older generation no longer binds, so confirming it does not change the sample that left
/// the screen.
public struct VisibleEntityContext: Hashable, Sendable {
    public let itemID: ItemID
    public let revision: Revision
    public let title: String
    public let generation: Int
    public let resolution: ContextResolution

    public init(itemID: ItemID, revision: Revision, title: String, generation: Int, resolution: ContextResolution) {
        self.itemID = itemID
        self.revision = revision
        self.title = title
        self.generation = generation
        self.resolution = resolution
    }

    /// Associates `item` at `generation`. A claim that does not match throws and returns nothing,
    /// so the caller keeps whatever was already on screen.
    public static func make(item: LabItem, claiming claim: SchemaClaim?, generation: Int) throws(ContextCardsError) -> VisibleEntityContext {
        if let claim, case .mismatch(let reason) = SchemaGate.decide(.labSample, claim: claim) {
            throw .schemaMismatch(reason)
        }
        return VisibleEntityContext(
            itemID: item.id, revision: item.revision, title: item.title.value,
            generation: generation, resolution: .unavailable
        )
    }
}

/// A set-aside captured against one sample.
///
/// `generation` is the screen's generation when the decision was made. `nil` means the Shortcut
/// named the sample itself and is not following the screen.
public struct DecisionProposal: Hashable, Sendable {
    public let itemID: ItemID
    public let revision: Revision
    public let generation: Int?
    public let title: String

    public init(itemID: ItemID, revision: Revision, generation: Int?, title: String) {
        self.itemID = itemID
        self.revision = revision
        self.generation = generation
        self.title = title
    }

    /// A decision for the sample now on screen, bound to that screen.
    public init(_ context: VisibleEntityContext) {
        self.init(itemID: context.itemID, revision: context.revision, generation: context.generation, title: context.title)
    }

    public var followsTheScreen: Bool { generation != nil }

    /// Whether confirming this decision would still be about `context`.
    ///
    /// An explicit Shortcut (no generation) does not follow the screen. A screen-bound decision
    /// binds only the same sample at the same generation.
    public func binds(_ context: VisibleEntityContext?) -> Bool {
        guard let generation else { return true }
        guard let context else { return false }
        return itemID == context.itemID && generation == context.generation
    }
}

/// The controls of the decision, in the app and in a snippet.
///
/// `siriEnabled` is accepted so a device can pass its Siri state. Both values return this same
/// card: a Siri-disabled device keeps Set Aside and Cancel.
public struct DecisionCard: Equatable, Sendable {
    public let title: String
    public let note: String
    public let prompt: String
    public let acceptLabel: String
    public let cancelLabel: String
    public let contextResolution: String

    public init(title: String, note: String, prompt: String, acceptLabel: String, cancelLabel: String, contextResolution: String) {
        self.title = title
        self.note = note
        self.prompt = prompt
        self.acceptLabel = acceptLabel
        self.cancelLabel = cancelLabel
        self.contextResolution = contextResolution
    }

    public static func showing(title: String, note: String, siriEnabled: Bool) -> DecisionCard {
        let card = DecisionCard(
            title: title,
            note: note,
            prompt: ContextCards.setAsidePrompt(title: title),
            acceptLabel: "Set Aside",
            cancelLabel: "Cancel",
            contextResolution: ContextCards.resolutionUnavailable
        )
        if siriEnabled { return card }
        return card
    }
}

/// The card's sample and any decision waiting on it. Showing a sample that fails the schema
/// gate leaves both as they were.
public struct ContextBoard: Equatable, Sendable {
    public private(set) var context: VisibleEntityContext?
    public private(set) var proposal: DecisionProposal?

    public init() {}

    public mutating func show(_ item: LabItem, claiming claim: SchemaClaim? = nil) throws(ContextCardsError) {
        let generation = (context?.generation ?? 0) + 1
        context = try VisibleEntityContext.make(item: item, claiming: claim, generation: generation)
    }

    /// Captures a decision for the sample on screen. It does not change the sample.
    public mutating func prepareDecision() {
        proposal = context.map(DecisionProposal.init)
    }

    public mutating func cancelDecision() { proposal = nil }

    /// A waiting decision whose sample is no longer the one on screen.
    public var decisionIsStale: Bool {
        guard let proposal else { return false }
        return !proposal.binds(context)
    }
}
