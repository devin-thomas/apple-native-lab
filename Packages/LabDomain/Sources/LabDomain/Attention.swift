import Foundation

/// Why a person asked the lab for attention (LAB-043). A reason is display text, never identity.
public struct AttentionReason: Hashable, Sendable, Codable, CustomStringConvertible {
    public static let maximumLength = 120

    public let value: String

    public init(_ raw: String) throws(ValidationError) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyReason }
        guard trimmed.count <= Self.maximumLength else { throw .reasonTooLong(limit: Self.maximumLength) }
        guard !trimmed.containsControlCharacter() else { throw .controlCharacter(in: .reason) }
        value = trimmed
    }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public var description: String { value }
}

/// The three ways this experiment asks for attention. Lab-owned names, not Apple symbols.
public enum AttentionChannel: String, Hashable, Sendable, Codable, CaseIterable {
    case reminder
    case focusFilter = "focus-filter"
    case alarm

    public var title: String {
        switch self {
        case .reminder: "Reminder"
        case .focusFilter: "Focus filter"
        case .alarm: "Alarm"
        }
    }
}

/// Whether the person took a separate action to schedule this alert.
///
/// Entering the experiment is not consent. Only `.explicit` can become a draft, so a schedule
/// cannot be built from a preview, a decoded suggestion, or a withheld choice.
public enum AttentionConsent: String, Hashable, Sendable, Codable {
    case explicit
    case withheld
}

/// A civil date and time in one named time zone.
///
/// The zone is part of the value. Resolving it never consults the device's current zone, so
/// changing that zone leaves the intended wall time in the stored zone where it was.
public struct CivilMoment: Hashable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let timeZoneIdentifier: String

    public init(
        year: Int, month: Int, day: Int, hour: Int, minute: Int, timeZoneIdentifier: String
    ) throws(ValidationError) {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { throw .unknownTimeZone }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else { throw .invalidMoment }
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard back.year == year, back.month == month, back.day == day, back.hour == hour, back.minute == minute else {
            throw .invalidMoment
        }
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier)! }

    /// The absolute instant of this civil time in its own zone.
    ///
    /// `deviceZone` is accepted and ignored. Callers pass the device zone they are not using, so a
    /// test can show that a zone change does not move the instant.
    public func instant(deviceZone: TimeZone) -> Date {
        _ = deviceZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Components for a calendar notification trigger. The time zone is set, so delivery stays on
    /// this civil time in this zone.
    public var dateComponents: DateComponents {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components
    }

    /// Wall time in the stored zone, plus the zone identifier. Independent of the device zone.
    public func label(deviceZone: TimeZone) -> String {
        _ = deviceZone
        return String(
            format: "%04d-%02d-%02d %02d:%02d %@",
            year, month, day, hour, minute, timeZoneIdentifier
        )
    }
}

/// A schedule the person has explicitly agreed to. Invalid input cannot be represented.
public struct AttentionDraft: Hashable, Sendable, Codable {
    public let id: AttentionID
    public let channel: AttentionChannel
    public let reason: AttentionReason
    public let moment: CivilMoment

    public init(
        id: AttentionID = AttentionID(),
        channel: AttentionChannel,
        reason: AttentionReason,
        moment: CivilMoment,
        consent: AttentionConsent
    ) throws(ValidationError) {
        guard consent == .explicit else { throw .consentRequired }
        self.init(id: id, channel: channel, reason: reason, moment: moment)
    }

    /// A draft whose consent was already checked, or that restores a stored alert.
    init(id: AttentionID, channel: AttentionChannel, reason: AttentionReason, moment: CivilMoment) {
        self.id = id
        self.channel = channel
        self.reason = reason
        self.moment = moment
    }

    private enum CodingKeys: String, CodingKey {
        case id, channel, reason, moment, consent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(AttentionID.self, forKey: .id),
            channel: container.decode(AttentionChannel.self, forKey: .channel),
            reason: container.decode(AttentionReason.self, forKey: .reason),
            moment: container.decode(CivilMoment.self, forKey: .moment),
            consent: container.decode(AttentionConsent.self, forKey: .consent)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(channel, forKey: .channel)
        try container.encode(reason, forKey: .reason)
        try container.encode(moment, forKey: .moment)
        try container.encode(AttentionConsent.explicit, forKey: .consent)
    }
}

/// The revision a caller last saw for one lab alert, for a cancel that must not race a newer edit.
public struct AttentionPin: Hashable, Sendable, Codable {
    public let id: AttentionID
    public let expected: Revision

    public init(id: AttentionID, expected: Revision) {
        self.id = id
        self.expected = expected
    }
}

/// One lab-owned alert. Always demo data: Reset Demo removes it, and it is never a person's
/// collection or a system Clock alarm.
public struct LabAttention: DomainEntity, Identifiable {
    public static let kind = EntityKind.attention

    public let id: AttentionID
    public let channel: AttentionChannel
    public let reason: AttentionReason
    public let moment: CivilMoment
    public let revision: Revision

    public init(
        id: AttentionID,
        channel: AttentionChannel,
        reason: AttentionReason,
        moment: CivilMoment,
        revision: Revision = .initial
    ) {
        self.id = id
        self.channel = channel
        self.reason = reason
        self.moment = moment
        self.revision = revision
    }

    public init(_ draft: AttentionDraft, revision: Revision = .initial) {
        self.init(id: draft.id, channel: draft.channel, reason: draft.reason, moment: draft.moment, revision: revision)
    }

    /// Always `demo`. A lab alert is experiment state, removed by Reset Demo and by Cancel Lab Alerts.
    public var namespace: DataNamespace { .demo }

    public var reference: EntityReference { .attention(id) }

    func matches(_ draft: AttentionDraft) -> Bool {
        channel == draft.channel && reason == draft.reason && moment == draft.moment
    }

    func revised(_ draft: AttentionDraft) -> LabAttention {
        LabAttention(draft, revision: revision.next())
    }

    /// The same content, for a receipt undo. The stored row exists only because consent was given.
    func draftForUndo() -> AttentionDraft {
        AttentionDraft(id: id, channel: channel, reason: reason, moment: moment)
    }
}
