import Foundation
import LabDomain

/// LAB-043 Respectful Attention: a reminder, a Focus filter, and an alarm, compared without
/// scheduling anything until a person asks.
public enum RespectfulAttention {
    public static let experimentID = "LAB-043"
    public static let title = "Respectful Attention"
    public static let symbol = "bell"

    /// Original fixtures. Neutral sample text, fixed IDs, one time zone.
    public static let offers: [AttentionOffer] = [
        AttentionOffer(
            id: AttentionID(rawValue: UUID(uuidString: "04300000-0000-4000-8000-000000000001")!),
            channel: .reminder,
            reason: "Review the sample notebook",
            moment: morning
        ),
        AttentionOffer(
            id: AttentionID(rawValue: UUID(uuidString: "04300000-0000-4000-8000-000000000003")!),
            channel: .focusFilter,
            reason: "Show only the lab agenda",
            moment: morning
        ),
        AttentionOffer(
            id: AttentionID(rawValue: UUID(uuidString: "04300000-0000-4000-8000-000000000002")!),
            channel: .alarm,
            reason: "Stand and stretch",
            moment: afternoon
        ),
    ]

    /// The Focus a person can select. It names lab alerts only and never changes the system Focus.
    public static let sampleFocus = FocusScope(
        name: "Lab Sample",
        included: Set(offers.map(\.id))
    )

    private static let morning = try! CivilMoment(
        year: 2026, month: 10, day: 1, hour: 9, minute: 0, timeZoneIdentifier: "America/Chicago"
    )
    private static let afternoon = try! CivilMoment(
        year: 2026, month: 10, day: 1, hour: 15, minute: 30, timeZoneIdentifier: "America/Chicago"
    )

    public static func offer(_ id: AttentionID) -> AttentionOffer? {
        offers.first { $0.id == id }
    }
}

/// A preview of one alert: when and why, before anything is scheduled.
public struct AttentionOffer: Hashable, Sendable, Identifiable {
    public let id: AttentionID
    public let channel: AttentionChannel
    public let reason: String
    public let moment: CivilMoment

    public init(id: AttentionID, channel: AttentionChannel, reason: String, moment: CivilMoment) {
        self.id = id
        self.channel = channel
        self.reason = reason
        self.moment = moment
    }

    public func preview(deviceZone: TimeZone) -> AttentionPreview {
        AttentionPreview(channel: channel, when: moment.label(deviceZone: deviceZone), why: reason)
    }

    /// The draft for a schedule. `consent` must be `.explicit`; a preview cannot become a draft.
    public func draft(consent: AttentionConsent) throws(ValidationError) -> AttentionDraft {
        try AttentionDraft(
            id: id, channel: channel, reason: AttentionReason(reason), moment: moment, consent: consent
        )
    }
}

/// When and why attention would be requested. Building one does not schedule anything.
public struct AttentionPreview: Hashable, Sendable {
    public let channel: AttentionChannel
    public let when: String
    public let why: String

    public init(channel: AttentionChannel, when: String, why: String) {
        self.channel = channel
        self.when = when
        self.why = why
    }
}
