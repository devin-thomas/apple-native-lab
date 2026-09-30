import AppIntents
import Foundation
import LabDomain

// Surface Deck's App Intents: one toggle, one read, and one launch action. The Control, the widget's
// toggle, and Shortcuts all run `SetDemoSessionIntent`; the Control's button and Shortcuts run
// `OpenSurfaceDeckIntent`. Each is a thin adapter: `perform()` hands the work to the host's
// `SessionBackend`, which commits through the same `OperationService` as the deck, as an App
// Intent (ADR-011). Neither intent needs a grant: starting or pausing the session is not
// destructive, and its undo is one tap away (ADR-013).

extension SessionSurface: AppEnum {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Surface"
    public static let caseDisplayRepresentations: [SessionSurface: DisplayRepresentation] = [
        .app: "Native Lab",
        .widget: "Widget",
        .control: "Control",
        .shortcuts: "Shortcuts",
    ]
}

/// Starts or pauses the demo session. A `SetValueIntent`, so a `ControlWidgetToggle` and a
/// widget `Toggle` can run it with the new value.
public struct SetDemoSessionIntent: SetValueIntent {
    public static let title: LocalizedStringResource = "Set Demo Session"
    public static let description = IntentDescription(
        "Starts or pauses Native Lab's demo session. The change leaves a receipt in the app with an undo."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication
    /// Runs without bringing the app forward: a widget or Control tap only changes the state.
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Running")
    public var value: Bool

    @Parameter(
        title: "Seen Revision",
        description: "Optional. The revision a widget or Control showed. If the session changed since, nothing is changed and the surface shows the current state."
    )
    public var seenRevision: Int?

    @Parameter(title: "Surface", description: "Optional. Where the change was made. It only labels the change.")
    public var surface: SessionSurface?

    @Dependency(default: SurfaceDeckLink.unavailable) private var deck: SurfaceDeckLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Set the demo session running: \(\.$value)") {
            \.$seenRevision
            \.$surface
        }
    }

    public init() {}

    /// The intent a surface offers for the state it shows: the opposite of what it shows, from
    /// the revision it shows. A widget toggle leaves `value` as given; a Control toggle may set it.
    public init(showing state: SessionState?, surface: SessionSurface) {
        value = !(state?.isRunning ?? false)
        seenRevision = (state?.seen ?? .unknown).parameter
        self.surface = surface
    }

    /// An intent that asks for `value`, as a surface that saw `seen`.
    public init(value: Bool, seen: SeenRevision, surface: SessionSurface) {
        self.value = value
        seenRevision = seen.parameter
        self.surface = surface
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let outcome = try await run(with: deck)
        return .result(value: outcome.state.isRunning, dialog: "\(outcome.message)")
    }

    /// The intent's work without the system.
    public func run(with link: SurfaceDeckLink) async throws(SurfaceDeckError) -> SessionOutcome {
        try await link.actions(.appIntent).setRunning(
            value, seen: SeenRevision(parameter: seenRevision), surface: surface ?? .shortcuts
        )
    }
}

#if os(iOS)
/// Where the toggle runs. Probed in the iOS 27.0 simulator (LAB-004-A): run from the widget, a plain
/// `SetValueIntent` performed in the widget extension, which has no store and so refused. As a
/// `LiveActivityIntent` it performed in the app's process, which the system launches in the
/// background when needed, so the change reaches the one `OperationService` with a receipt. The
/// conformance is for that routing only; the lab starts no Live Activity. iOS only, as the
/// protocol is.
extension SetDemoSessionIntent: LiveActivityIntent {}
#endif

/// Reads whether the demo session is running. Read-only.
public struct GetDemoSessionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Demo Session"
    public static let description = IntentDescription("Reads whether Native Lab's demo session is running.")
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Dependency(default: SurfaceDeckLink.unavailable) private var deck: SurfaceDeckLink

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let state = try await run(with: deck)
        return .result(value: state.isRunning, dialog: "\(Self.dialog(for: state))")
    }

    public func run(with link: SurfaceDeckLink) async throws(SurfaceDeckError) -> SessionState {
        try await link.actions(.appIntent).current()
    }

    static func dialog(for state: SessionState) -> String {
        state.revision == nil ? "The demo session has never been started." : "The demo session is \(state.title.lowercased())."
    }
}

/// Where the launch action opens. One place today; an `OpenIntent` needs a value to open.
public enum SurfaceDeckDestination: String, AppEnum {
    case deck

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Destination"
    public static let caseDisplayRepresentations: [SurfaceDeckDestination: DisplayRepresentation] = [.deck: "Surface Deck"]
}

/// Opens Native Lab at the Surface Deck: the launch action. An `OpenIntent`, which a Control button
/// needs to bring its app forward; it runs in the app, in the foreground.
public struct OpenSurfaceDeckIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Surface Deck"
    public static let description = IntentDescription(
        "Opens Native Lab's Surface Deck: the demo session, its receipts, and previews of its widget and Control."
    )
    public static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Destination", default: .deck)
    public var target: SurfaceDeckDestination

    @Dependency(default: SurfaceDeckLink.unavailable) private var deck: SurfaceDeckLink

    public init() {}

    public func perform() async throws -> some IntentResult {
        await deck.open()
        return .result()
    }
}

/// Lets a host app, or the widget extension, include these intents in its App Intents metadata.
public struct SurfaceDeckIntentsPackage: AppIntentsPackage {}
