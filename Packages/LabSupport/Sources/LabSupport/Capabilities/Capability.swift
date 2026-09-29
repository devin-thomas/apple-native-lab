/// A capability the lab can probe without prompting.
///
/// Each case carries static facts: which platforms compile its probe, which framework and
/// symbols it reads, what the signed build must carry, and the documented alternate route.
public enum Capability: String, CaseIterable, Sendable, Codable, Identifiable {
    case camera
    case microphone
    case speechRecognition = "speech-recognition"
    case onDeviceLanguageModel = "on-device-language-model"
    case worldTracking = "world-tracking"
    case sceneReconstruction = "scene-reconstruction"
    case ultraWideband = "ultra-wideband"
    case bluetooth
    case localNetwork = "local-network"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .speechRecognition: "Speech recognition"
        case .onDeviceLanguageModel: "On-device language model"
        case .worldTracking: "AR world tracking"
        case .sceneReconstruction: "AR scene reconstruction"
        case .ultraWideband: "Ultra Wideband ranging"
        case .bluetooth: "Bluetooth"
        case .localNetwork: "Local network"
        }
    }

    /// Platforms whose build compiles this probe. Every other platform leaves the framework out.
    public var probedPlatforms: Set<LabPlatform> {
        switch self {
        case .camera, .speechRecognition, .onDeviceLanguageModel: [.iOS, .macOS]
        case .microphone: [.iOS, .macOS, .watchOS]
        case .worldTracking, .sceneReconstruction: [.iOS]
        case .ultraWideband: [.iOS, .watchOS]
        case .bluetooth: [.iOS, .macOS, .watchOS, .tvOS]
        case .localNetwork: [.iOS, .macOS, .tvOS]
        }
    }

    /// The framework whose symbols the probe reads on a platform, or `nil` when it reads none.
    public func framework(on platform: LabPlatform) -> String? {
        switch self {
        case .camera: "AVFoundation"
        case .microphone: platform == .watchOS ? "AVFAudio" : "AVFoundation"
        case .speechRecognition: "Speech"
        case .onDeviceLanguageModel: "FoundationModels"
        case .worldTracking, .sceneReconstruction: "ARKit"
        case .ultraWideband: "NearbyInteraction"
        case .bluetooth: "CoreBluetooth"
        case .localNetwork: nil
        }
    }

    /// The exact SDK symbols the probe reads on a platform. None of them prompts.
    public func probedSymbols(on platform: LabPlatform) -> [String] {
        switch self {
        case .camera:
            ["AVCaptureDevice.authorizationStatus(for: .video)", "AVCaptureDevice.default(for: .video)"]
        case .microphone where platform == .watchOS:
            ["AVAudioApplication.shared.recordPermission", "AVAudioSession.sharedInstance().isInputAvailable"]
        case .microphone:
            ["AVCaptureDevice.authorizationStatus(for: .audio)", "AVCaptureDevice.default(for: .audio)"]
        case .speechRecognition:
            ["SFSpeechRecognizer.authorizationStatus()", "SpeechTranscriber.isAvailable",
             "SpeechTranscriber.supportedLocale(equivalentTo:)", "SpeechTranscriber.installedLocales"]
        case .onDeviceLanguageModel:
            ["SystemLanguageModel.default.availability", "SystemLanguageModel.default.supportsLocale(_:)"]
        case .worldTracking:
            ["ARWorldTrackingConfiguration.isSupported", "AVCaptureDevice.authorizationStatus(for: .video)"]
        case .sceneReconstruction:
            ["ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)",
             "AVCaptureDevice.authorizationStatus(for: .video)"]
        case .ultraWideband:
            ["NISession.deviceCapabilities"]
        case .bluetooth:
            ["CBManager.authorization"]
        case .localNetwork:
            []
        }
    }

    /// Whether the hardware gate describes a physical sensor or radio, which a simulator cannot
    /// provide evidence for.
    public var isPhysicalSensor: Bool {
        switch self {
        case .camera, .microphone, .worldTracking, .sceneReconstruction, .ultraWideband, .bluetooth: true
        case .speechRecognition, .onDeviceLanguageModel, .localNetwork: false
        }
    }

    /// The permission a feature must hold, if any.
    public var permission: PermissionKind? {
        switch self {
        case .camera, .worldTracking, .sceneReconstruction: .camera
        case .microphone: .microphone
        case .speechRecognition: .speechRecognition
        case .onDeviceLanguageModel: nil
        case .ultraWideband: .nearbyInteraction
        case .bluetooth: .bluetooth
        case .localNetwork: .localNetwork
        }
    }

    /// Entitlements a sandboxed, hardened-runtime Mac build needs. The lab's Mac host is both.
    /// iOS, watchOS, and tvOS need none for these capabilities.
    public func requiredEntitlements(on platform: LabPlatform) -> [String] {
        guard platform == .macOS else { return [] }
        return switch self {
        case .camera: ["com.apple.security.device.camera"]
        case .microphone: ["com.apple.security.device.audio-input"]
        case .bluetooth: ["com.apple.security.device.bluetooth"]
        case .localNetwork: ["com.apple.security.network.client", "com.apple.security.network.server"]
        case .speechRecognition, .onDeviceLanguageModel, .worldTracking, .sceneReconstruction, .ultraWideband: []
        }
    }

    /// The route a feature takes when this capability is unavailable, denied, or unknown.
    public var fallback: FallbackRoute {
        switch self {
        case .camera:
            FallbackRoute("Use the original sample frames, or import an image you choose.",
                          experiments: ["LAB-026", "LAB-012"])
        case .microphone:
            FallbackRoute("Import an original audio fixture, or pick the reference clip and time by hand. Nothing records.",
                          experiments: ["LAB-013", "LAB-028"])
        case .speechRecognition:
            FallbackRoute("Import a caption fixture or annotate the transcript by hand. Unsupported languages are named.",
                          experiments: ["LAB-013"])
        case .onDeviceLanguageModel:
            FallbackRoute("Use the deterministic sample parser and manual editor, labeled as non-model paths.",
                          experiments: ["LAB-010"])
        case .worldTracking:
            FallbackRoute("Explore the orbitable 3D scene with touch or pointer controls.",
                          experiments: ["LAB-023"])
        case .sceneReconstruction:
            FallbackRoute("Review the bundled fictional room and enter dimensions by hand.",
                          experiments: ["LAB-024"])
        case .ultraWideband:
            FallbackRoute("Drive the instrument with a manual distance slider or labeled synthetic measurements.",
                          experiments: ["LAB-022"])
        case .bluetooth:
            FallbackRoute("Use the software peripheral simulator and its contract tests.",
                          experiments: ["LAB-047"])
        case .localNetwork:
            FallbackRoute("Run the single-device conductor and client simulation with identical wire messages.",
                          experiments: ["LAB-019"])
        }
    }

    /// Capabilities whose probes this platform's build compiles, in display order.
    public static func probed(on platform: LabPlatform) -> [Capability] {
        allCases.filter { $0.probedPlatforms.contains(platform) }
    }

    /// Capabilities this platform's build leaves out entirely.
    public static func excluded(on platform: LabPlatform) -> [Capability] {
        allCases.filter { !$0.probedPlatforms.contains(platform) }
    }
}

/// A documented alternate route. Every capability has one, so an unavailable or denied
/// capability still leads somewhere useful (docs/EXTENSION_AND_PERMISSION_MATRIX.md).
public struct FallbackRoute: Sendable, Equatable, Hashable {
    public var summary: String
    /// The experiment specs that declare this fallback.
    public var experiments: [String]

    public init(_ summary: String, experiments: [String]) {
        self.summary = summary
        self.experiments = experiments
    }
}
