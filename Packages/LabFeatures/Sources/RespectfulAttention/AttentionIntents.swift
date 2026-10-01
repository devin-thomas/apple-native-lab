import AppIntents
import Foundation
import LabDomain

/// Schedules one sample lab alert after the person confirms. The confirmation is the consent.
public struct ScheduleLabAlertIntent: AppIntent {
    public static let title: LocalizedStringResource = "Schedule Lab Alert"
    public static let description = IntentDescription(
        "Adds one sample lab alert to Native Lab's agenda after you confirm. It does not use the system Clock."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Alert")
    public var choice: LabAlertChoice

    @Dependency(default: RespectfulAttentionLink.unavailable) private var link: RespectfulAttentionLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Schedule \(\.$choice)")
    }

    public init() { choice = .reminder }

    public init(choice: LabAlertChoice) { self.choice = choice }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let output = try await run(with: link) { prompt in
            try await requestConfirmation(
                actionName: .custom(
                    acceptLabel: "Schedule", acceptAlternatives: [],
                    denyLabel: "Cancel", denyAlternatives: [],
                    destructive: false
                ),
                dialog: "\(prompt)"
            )
        }
        return .result(dialog: "\(output)")
    }

    /// The intent's work without the system. `confirm` stands in for the confirmation dialog.
    public func run(
        with link: RespectfulAttentionLink,
        confirm: @Sendable (String) async throws -> Void
    ) async throws -> String {
        let offer = choice.offer
        let preview = offer.preview(deviceZone: .current)
        try await confirm("\(preview.channel.title): \(preview.why). \(preview.when)")
        let outcome = try await link.actions(.appIntent).schedule(offer, consent: .explicit)
        return outcome.receipt.summary
    }
}

/// Cancels every lab alert after the person confirms. Other pending alerts are not named.
public struct CancelLabAlertsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Cancel Lab Alerts"
    public static let description = IntentDescription(
        "Cancels Native Lab's own alerts after you confirm. It does not cancel other apps' alerts or Clock alarms."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Dependency(default: RespectfulAttentionLink.unavailable) private var link: RespectfulAttentionLink

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let output = try await run(with: link) { operation, prompt in
            try await requestConfirmation(
                actionName: .custom(
                    acceptLabel: "Cancel Alerts", acceptAlternatives: [],
                    denyLabel: "Keep", denyAlternatives: [],
                    destructive: true
                ),
                dialog: "\(prompt)"
            )
            return AttentionConfirmation(confirmed: operation)
        }
        return .result(dialog: "\(output)")
    }

    public func run(
        with link: RespectfulAttentionLink,
        confirm: @Sendable (DomainOperation, String) async throws -> AttentionConfirmation
    ) async throws -> String {
        let actions = link.actions(.appIntent)
        let current = try await actions.attentions()
        let operation = DomainOperation.cancelLabAlerts(
            pins: current.map { AttentionPin(id: $0.id, expected: $0.revision) }
        )
        let confirmation = try await confirm(operation, "Cancel \(current.count) lab alerts? Other alerts stay.")
        let outcome = try await actions.commit(operation, confirmation: confirmation)
        return outcome.receipt.summary
    }
}

public enum LabAlertChoice: String, AppEnum, Sendable {
    case reminder
    case focusFilter
    case alarm

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Lab Alert")
    public static let caseDisplayRepresentations: [LabAlertChoice: DisplayRepresentation] = [
        .reminder: "Sample reminder",
        .focusFilter: "Sample Focus filter",
        .alarm: "Sample alarm",
    ]

    var offer: AttentionOffer {
        switch self {
        case .reminder: RespectfulAttention.offers[0]
        case .focusFilter: RespectfulAttention.offers[1]
        case .alarm: RespectfulAttention.offers[2]
        }
    }
}

/// The app's Focus filter. The system calls it when a person adds Native Lab to a Focus.
/// It filters lab notification identifiers and does not change the Focus itself.
public struct LabFocusFilterIntent: SetFocusFilterIntent {
    public static let title: LocalizedStringResource = "Lab Agenda Focus"
    public static let description = IntentDescription(
        "Shows only Native Lab's own alerts while this Focus is on. It does not change the Focus."
    )

    @Parameter(title: "Included Lab Alerts")
    public var includedIdentifiers: [String]?

    public init() {
        includedIdentifiers = RespectfulAttention.offers.map { LabAlertIdentity.notificationID($0.id) }
    }

    public init(includedIdentifiers: [String]) {
        self.includedIdentifiers = includedIdentifiers
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Lab Sample")
    }

    /// Lab-owned notification identifiers only. A foreign identifier in the parameter is dropped
    /// before the predicate is built, so the filter cannot name another app's alerts.
    public static func notificationPredicate(includedIdentifiers: [String]) -> NSPredicate {
        NSPredicate(format: "request.identifier IN %@", FocusScope.labOwned(in: includedIdentifiers) as NSArray)
    }

    public var appContext: FocusFilterAppContext {
        FocusFilterAppContext(
            notificationFilterPredicate: Self.notificationPredicate(includedIdentifiers: includedIdentifiers ?? [])
        )
    }

    public static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [LabFocusFilterIntent] {
        [LabFocusFilterIntent()]
    }

    public func perform() async throws -> some IntentResult {
        .result()
    }
}

public struct RespectfulAttentionIntentsPackage: AppIntentsPackage {}
