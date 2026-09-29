/// A protected resource the system asks the person about.
public enum PermissionKind: String, CaseIterable, Sendable, Codable {
    case camera
    case microphone
    case speechRecognition = "speech-recognition"
    case bluetooth
    case nearbyInteraction = "nearby-interaction"
    case localNetwork = "local-network"

    public var title: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .speechRecognition: "Speech recognition"
        case .bluetooth: "Bluetooth"
        case .nearbyInteraction: "Nearby Interaction"
        case .localNetwork: "Local network"
        }
    }

    /// The Info.plist purpose string the system requires before it shows this prompt, or `nil`
    /// when the system supplies a default. Asking without a required string ends the process.
    public var purposeStringKey: String? {
        switch self {
        case .camera: "NSCameraUsageDescription"
        case .microphone: "NSMicrophoneUsageDescription"
        case .speechRecognition: "NSSpeechRecognitionUsageDescription"
        case .bluetooth: "NSBluetoothAlwaysUsageDescription"
        case .nearbyInteraction: "NSNearbyInteractionUsageDescription"
        case .localNetwork: nil
        }
    }

    /// Why the status cannot be read without asking, or `nil` when it can.
    public var unreadableReason: String? {
        switch self {
        case .nearbyInteraction:
            "No API reads Nearby Interaction permission in advance. The system asks when a feature runs an NISession."
        case .localNetwork:
            "No API reads local network permission in advance. The system asks on first local traffic, and a denial appears only as NWPath.UnsatisfiedReason.localNetworkDenied on a connection the feature starts."
        case .camera, .microphone, .speechRecognition, .bluetooth:
            nil
        }
    }

    /// Whether the lab can ask for this permission by itself. Otherwise the system asks when
    /// the feature starts its session, such as creating a Bluetooth manager.
    public var isDirectlyRequestable: Bool {
        switch self {
        case .camera, .microphone, .speechRecognition: true
        case .bluetooth, .nearbyInteraction, .localNetwork: false
        }
    }
}

/// A permission status read without prompting.
public enum PermissionStatus: String, CaseIterable, Sendable, Codable {
    case notDetermined = "not-determined"
    case authorized
    case denied
    case restricted
    /// The platform offers no way to read this status without asking.
    case notReadable = "not-readable"
    /// The SDK returned a value this code does not recognize.
    case unrecognized

    public var title: String {
        switch self {
        case .notDetermined: "Not asked yet"
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notReadable: "Not readable"
        case .unrecognized: "Unrecognized"
        }
    }

    var gateState: GateState {
        switch self {
        case .authorized: .met
        case .notDetermined: .needsAction
        case .denied: .denied
        case .restricted: .restricted
        case .notReadable, .unrecognized: .unknown
        }
    }
}
