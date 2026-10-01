import Foundation
import LabDomain
import Testing

/// LAB-043: lab alerts change only through `OperationService`, with a receipt, under the same
/// adapter ceilings as every other operation.
@Suite struct AttentionTests {
    private func moment(hour: Int = 9, zone: String = "America/Chicago") throws -> CivilMoment {
        try CivilMoment(year: 2026, month: 10, day: 1, hour: hour, minute: 0, timeZoneIdentifier: zone)
    }

    private func draft(
        _ id: AttentionID,
        channel: AttentionChannel = .reminder,
        reason: String = "Review the sample notebook",
        hour: Int = 9,
        consent: AttentionConsent = .explicit
    ) throws -> AttentionDraft {
        try AttentionDraft(
            id: id, channel: channel, reason: AttentionReason(reason), moment: moment(hour: hour), consent: consent
        )
    }

    @Test func anExplicitScheduleIsRecordedAndItsUndoCancelsOnlyThatAlert() async throws {
        let lab = Harness()
        let id = AttentionID(rawValue: uuid(800))
        let other = AttentionID(rawValue: uuid(801))
        let receipt = try await lab.perform(.scheduleAttention(expected: nil, draft: draft(id)))
        _ = try await lab.perform(.scheduleAttention(expected: nil, draft: draft(other, reason: "Stand and stretch", hour: 15)))
        #expect(receipt.status == .committed)
        #expect(receipt.summary.contains("Review the sample notebook"))
        #expect(receipt.undo == .cancelLabAlerts(pins: [AttentionPin(id: id, expected: .initial)]))

        let undone = try await lab.perform(try #require(receipt.undo))
        #expect(undone.removed.map(\.rawID) == [id.rawValue])
        #expect(try await lab.service.findAttention(id, as: .appUI) == nil)
        #expect(try await lab.service.findAttention(other, as: .appUI) != nil)
    }

    @Test func cancelRemovesOnlyTheNamedAlerts() async throws {
        let lab = Harness()
        let kept = AttentionID(rawValue: uuid(802))
        let removed = AttentionID(rawValue: uuid(803))
        _ = try await lab.perform(.scheduleAttention(expected: nil, draft: draft(kept)))
        _ = try await lab.perform(.scheduleAttention(expected: nil, draft: draft(removed, channel: .alarm, reason: "Stand and stretch")))
        let receipt = try await lab.perform(.cancelLabAlerts(pins: [AttentionPin(id: removed, expected: .initial)]))
        #expect(receipt.removed == [.attention(removed)])
        #expect(try await lab.service.findAttentions(as: .appUI).map(\.id) == [kept])
        let restored = try await lab.perform(try #require(receipt.undo))
        #expect(restored.summary == "Restored 1 lab alert.")
        #expect(try await lab.service.findAttention(removed, as: .appUI)?.channel == .alarm)
    }

    @Test func aWithheldConsentCannotBecomeADraft() {
        let id = AttentionID(rawValue: uuid(804))
        #expect(throws: ValidationError.consentRequired) {
            try draft(id, consent: .withheld)
        }
    }

    @Test func invalidMomentsAndReasonsAreRefused() throws {
        #expect(throws: ValidationError.invalidMoment) {
            try CivilMoment(year: 2026, month: 2, day: 31, hour: 9, minute: 0, timeZoneIdentifier: "America/Chicago")
        }
        #expect(throws: ValidationError.unknownTimeZone) {
            try CivilMoment(year: 2026, month: 10, day: 1, hour: 9, minute: 0, timeZoneIdentifier: "Not/AZone")
        }
        #expect(throws: ValidationError.emptyReason) { try AttentionReason("  ") }
        #expect(throws: ValidationError.reasonTooLong(limit: 120)) {
            try AttentionReason(String(repeating: "a", count: 121))
        }
    }

    @Test func theStoredZoneDoesNotFollowTheDeviceZone() throws {
        let moment = try moment()
        let chicago = TimeZone(identifier: "America/Chicago")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let newYork = TimeZone(identifier: "America/New_York")!
        #expect(moment.instant(deviceZone: tokyo) == moment.instant(deviceZone: newYork))
        #expect(moment.label(deviceZone: tokyo) == moment.label(deviceZone: newYork))
        #expect(moment.label(deviceZone: tokyo).contains("America/Chicago"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = chicago
        #expect(moment.instant(deviceZone: newYork) == calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9, minute: 0)))
        calendar.timeZone = newYork
        let shifted = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9, minute: 0))!
        #expect(moment.instant(deviceZone: newYork) != shifted)
    }

    @Test func aStaleScheduleConflictsAndADuplicateRequestReturnsTheSameReceipt() async throws {
        let lab = Harness()
        let id = AttentionID(rawValue: uuid(805))
        let request = RequestID(rawValue: uuid(806))
        let first = try await lab.perform(.scheduleAttention(expected: nil, draft: draft(id)), id: request)
        let again = try await lab.perform(.scheduleAttention(expected: nil, draft: draft(id)), id: request)
        #expect(again == first)
        await #expect(throws: OperationError.requestIDReused(request)) {
            try await lab.perform(.scheduleAttention(expected: nil, draft: draft(id, hour: 10)), id: request)
        }
        #expect(try await lab.service.findAttention(id, as: .appUI)?.moment.hour == 9)
        let stale = try await lab.perform(.scheduleAttention(expected: .r(2), draft: draft(id, hour: 12)))
        let conflict = try #require(stale.conflict)
        #expect(conflict.entity == .attention(id))
        #expect(conflict.expected == .r(2))
        #expect(conflict.current == .initial)
        #expect(try await lab.service.findAttention(id, as: .appUI)?.moment.hour == 9)
        let updated = try await lab.perform(.scheduleAttention(expected: .initial, draft: draft(id, hour: 11)))
        #expect(updated.conflict == nil)
        #expect(try await lab.service.findAttention(id, as: .appUI)?.moment.hour == 11)
    }

    @Test func cancellingNothingAndAnEmptyRestoreChangeNothing() async throws {
        let lab = Harness()
        await #expect(throws: OperationError.ruleViolation(.nothingToCancel)) {
            try await lab.perform(.cancelLabAlerts(pins: []))
        }
        await #expect(throws: OperationError.ruleViolation(.nothingToCancel)) {
            try await lab.perform(.restoreLabAlerts(drafts: []))
        }
        #expect(await lab.appliedCommits == 0)
    }

    @Test func aModelToolCanProposeButCannotCommitAndAResetRemovesOnlyAlerts() async throws {
        let lab = Harness()
        let id = AttentionID(rawValue: uuid(807))
        let operation = DomainOperation.scheduleAttention(expected: nil, draft: try draft(id))
        let proposal = try await lab.service.propose(operation, as: .modelTool)
        #expect(proposal.operation == operation)
        await #expect(throws: OperationError.self) {
            try await lab.perform(operation, as: .modelTool)
        }
        _ = try await lab.perform(operation)
        let kept = try await lab.makeCollection("Kept", id: CollectionID(rawValue: uuid(808)))
        let seed = try DemoSeed(
            version: 1,
            collections: [CollectionDraft(id: CollectionID(rawValue: uuid(810)), title: "Samples")],
            items: []
        )
        let reset = try await lab.perform(.resetDemo(seed: seed))
        #expect(reset.removed == [.attention(id)])
        #expect(try await lab.service.findAttention(id, as: .appUI) == nil)
        #expect(try await lab.service.findCollection(kept.id, as: .appUI).title.value == "Kept")
    }

    @Test func aReceiptRoundTripsTheAlert() async throws {
        let lab = Harness()
        let id = AttentionID(rawValue: uuid(809))
        let receipt = try await lab.perform(.scheduleAttention(expected: nil, draft: draft(id, channel: .focusFilter)))
        let data = try JSONEncoder().encode(receipt)
        #expect(try JSONDecoder().decode(ActionReceipt.self, from: data) == receipt)
        #expect(String(decoding: data, as: UTF8.self).contains("focus-filter"))
    }
}
