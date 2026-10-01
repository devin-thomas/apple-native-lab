#if os(macOS)
import AppIntents
import Foundation

/// The commands an intent may run. The parameter is this enum, not a string, so a shortcut cannot
/// hand the lab text to execute. Shell-shaped text is not a case.
public enum AllowlistedDesktopCommand: String, AppEnum, Sendable {
    case importFixtureNote = "import-fixture-note"
    case showStatus = "show-status"

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Desktop Command"

    public static let caseDisplayRepresentations: [AllowlistedDesktopCommand: DisplayRepresentation] = [
        .importFixtureNote: "Import Fixture Note",
        .showStatus: "Show Desktop Status",
    ]

    public var command: ScriptableCommand {
        switch self {
        case .importFixtureNote: .importFixtureNote
        case .showStatus: .showStatus
        }
    }
}

/// The handle the Mac host registers at launch. Until it does, the intent refuses to run.
public final class DesktopPowerLink: Sendable {
    public let station: DesktopStation?

    public init(station: DesktopStation?) {
        self.station = station
    }

    public static let unavailable = DesktopPowerLink(station: nil)
}

/// The one automation entry point for this experiment. It runs an allowlisted command through
/// the same station as the menus, as an App Intent, and it does not receive shell text.
public struct RunDesktopCommandIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Desktop Command"
    public static let description = IntentDescription(
        "Imports the bundled desktop fixture note, or reports how many notes and windows are open. It does not run typed commands or shell text."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Command", default: .showStatus)
    public var command: AllowlistedDesktopCommand

    @Dependency(default: DesktopPowerLink.unavailable) private var link: DesktopPowerLink

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$command)")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await run(with: link)
    }

    /// What `perform()` does, so a test can pass a link without the system.
    @MainActor
    public func run(with link: DesktopPowerLink) async throws -> some IntentResult & ProvidesDialog {
        guard let station = link.station else { throw DesktopPowerError.unavailable }
        let outcome = try await station.performAllowlisted(command.command, as: .appIntent)
        let dialog: String
        switch outcome {
        case .status(let status):
            dialog = status.summary
        case .imported(let imported):
            dialog = imported.receipt?.summary ?? "Imported \(imported.document.title)."
        }
        return .result(dialog: "\(dialog)")
    }
}

public struct DesktopNativePowerIntentsPackage: AppIntentsPackage {}
#endif
