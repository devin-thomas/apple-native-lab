import Foundation

/// The `NSUserActivity` a continuation advertises.
///
/// The activity type has to be listed in the host's `NSUserActivityTypes`. The same team has to
/// sign both devices before the system will deliver it, which this build does not claim to have
/// tried. The activity's user info is the continuation payload and nothing more: search indexing,
/// public indexing, a web page, and continuation streams stay off, so the system is not asked to
/// fetch a page or open a stream back to the draft.
public enum HandoffActivity {
    public static let activityType = "nativelab.pick-up-here"
    /// Shown on the other device. It is not the draft's title.
    public static let title = "Pick Up Here"

    public static func make(from offer: ContinuationOffer, handoffEligible: Bool) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        fill(activity, with: offer, handoffEligible: handoffEligible)
        return activity
    }

    public static func fill(_ activity: NSUserActivity, with offer: ContinuationOffer, handoffEligible: Bool) {
        activity.title = title
        activity.userInfo = offer.userInfo
        activity.requiredUserInfoKeys = Set(ContinuationPayload.keys)
        activity.isEligibleForHandoff = handoffEligible
        activity.isEligibleForSearch = false
        activity.isEligibleForPublicIndexing = false
        activity.supportsContinuationStreams = false
        activity.webpageURL = nil
        activity.keywords = []
    }

    public static func token(from activity: NSUserActivity) throws(PickUpError) -> ContinuationToken {
        guard activity.activityType == activityType, let userInfo = activity.userInfo else { throw .invalidPayload }
        return try ContinuationPayload.token(from: userInfo)
    }
}
