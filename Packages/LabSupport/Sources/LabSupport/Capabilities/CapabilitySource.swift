/// Read-only access to the platform facts a probe needs.
///
/// Nothing on this protocol can show a permission prompt: it reads statuses and support flags
/// only. Requests live on `PermissionRequesting`, which only `PermissionStager` holds. The live
/// implementation calls platform frameworks; tests supply fakes.
public protocol CapabilitySource: Sendable {
    /// Whether this is a simulator, whose sensor readings are simulated rather than hardware.
    var isSimulator: Bool { get }
    /// A permission status read without prompting.
    func permissionStatus(_ permission: PermissionKind) -> PermissionStatus
    /// Whether a capture device of this kind is present, or `nil` when not measurable here.
    func hasCaptureDevice(_ kind: CaptureDeviceKind) -> Bool?
    /// Speech transcription support and the asset state for the current locale.
    func speechTranscription() async -> SpeechTranscriptionReading
    /// The system language model's availability.
    func languageModel() -> LanguageModelReading
    /// ARKit support flags, or `nil` when ARKit is not compiled for this platform.
    func worldTracking() -> WorldTrackingReading?
    /// Ultra Wideband capabilities, or `nil` when Nearby Interaction is not compiled here.
    func ultraWideband() -> UltraWidebandReading?
    /// Whether the signed build carries an entitlement.
    func entitlement(_ key: String) -> EntitlementReading
    /// Whether the bundle declares a non-empty Info.plist string for this key.
    func declaresPurposeString(_ key: String) -> Bool
}

public enum CaptureDeviceKind: String, Sendable {
    case video
    case audio
}

public enum EntitlementReading: String, Sendable, Equatable {
    case present
    case absent
    /// This platform offers no public way to read the running build's entitlements.
    case notReadable = "not-readable"
}

/// A mirror of `SystemLanguageModel` availability, so tests need no model on the host.
public struct LanguageModelReading: Sendable, Equatable {
    public enum Availability: Sendable, Equatable {
        case available
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        /// A reason the SDK added after this code was written.
        case unrecognized(String)
        /// FoundationModels is not compiled for this platform.
        case notCompiled
    }

    public var availability: Availability
    /// `SystemLanguageModel.supportsLocale(_:)` for the current locale, or `nil` when not read.
    public var supportsCurrentLocale: Bool?
    public var localeIdentifier: String

    public init(availability: Availability, supportsCurrentLocale: Bool?, localeIdentifier: String) {
        self.availability = availability
        self.supportsCurrentLocale = supportsCurrentLocale
        self.localeIdentifier = localeIdentifier
    }
}

public struct SpeechTranscriptionReading: Sendable, Equatable {
    public enum Asset: Sendable, Equatable {
        /// The on-device model for the locale is installed.
        case installed
        /// The locale is supported and its model can be downloaded by a feature action.
        case downloadable
        /// No on-device model exists for the locale.
        case unsupportedLocale
        /// Not measured, such as when the transcriber is unavailable.
        case unknown
    }

    /// `SpeechTranscriber.isAvailable`, or `nil` when Speech is not compiled here.
    public var transcriberAvailable: Bool?
    /// The locale identifier that was checked.
    public var localeIdentifier: String
    public var asset: Asset

    public init(transcriberAvailable: Bool?, localeIdentifier: String, asset: Asset) {
        self.transcriberAvailable = transcriberAvailable
        self.localeIdentifier = localeIdentifier
        self.asset = asset
    }
}

public struct WorldTrackingReading: Sendable, Equatable {
    /// `ARWorldTrackingConfiguration.isSupported`.
    public var worldTracking: Bool
    /// `ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)`.
    public var sceneReconstruction: Bool

    public init(worldTracking: Bool, sceneReconstruction: Bool) {
        self.worldTracking = worldTracking
        self.sceneReconstruction = sceneReconstruction
    }
}

public struct UltraWidebandReading: Sendable, Equatable {
    /// `NIDeviceCapability.supportsPreciseDistanceMeasurement`.
    public var preciseDistance: Bool
    /// `NIDeviceCapability.supportsDirectionMeasurement`.
    public var direction: Bool

    public init(preciseDistance: Bool, direction: Bool) {
        self.preciseDistance = preciseDistance
        self.direction = direction
    }
}
