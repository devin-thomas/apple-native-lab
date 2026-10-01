import ActionAtlas
import AppIntents
import Foundation
import LabDomain
import Synchronization

/// Fills an `NSUserActivity` for the sample on screen.
///
/// The activity carries the sample's entity identifier and is not offered for Handoff. Siri
/// suggestions are a separate gate; the prediction switch exists only on iOS and watchOS.
public enum VisibleSampleActivity {
    public static func identifier(for itemID: UUID) -> EntityIdentifier {
        EntityIdentifier(for: LabItemEntity.self, identifier: itemID)
    }

    public static func fill(_ activity: NSUserActivity, title: String, itemID: UUID) {
        activity.title = title
        activity.appEntityIdentifier = identifier(for: itemID)
        // Eligible for prediction is iOS and watchOS only. The Mac and Apple TV have no such switch,
        // and this activity is not offered for Handoff. Siri suggestions stay a separate gate.
        #if os(iOS) || os(watchOS)
        activity.isEligibleForPrediction = false
        #endif
        activity.isEligibleForHandoff = false
    }
}

/// The handle the card and the Shortcut share.
///
/// The host registers one at launch, over the same library Action Atlas uses. Until it does,
/// `unavailable` refuses every request. `publish` is the sample on screen; a decision bound to
/// an older generation will not change that sample.
public final class ContextCardsLink: Sendable {
    public let atlas: ActionAtlasLink
    private let screen = Mutex<VisibleEntityContext?>(nil)

    public init(atlas: ActionAtlasLink) {
        self.atlas = atlas
    }

    public static let unavailable = ContextCardsLink(atlas: .unavailable)

    public func publish(_ context: VisibleEntityContext?) {
        screen.withLock { $0 = context }
    }

    public var visible: VisibleEntityContext? { screen.withLock { $0 } }

    public func actions(_ entryPoint: AtlasEntryPoint) -> ContextCardsActions {
        ContextCardsActions(atlas: atlas.actions(entryPoint), visible: { self.visible })
    }
}
