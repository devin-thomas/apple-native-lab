import Foundation

// Every framework import is guarded by both `canImport` and `os`. `canImport` alone is not
// enough: the 27.0 macOS SDK ships an ARKit module with a different API, and the watchOS and
// tvOS SDKs ship FoundationModels even though SystemLanguageModel is unavailable there.
#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import AVFoundation
#endif
#if canImport(AVFAudio) && os(watchOS)
import AVFAudio
#endif
#if canImport(Speech) && (os(iOS) || os(macOS))
import Speech
#endif
#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import FoundationModels
#endif
#if canImport(ARKit) && os(iOS) && !targetEnvironment(macCatalyst)
import ARKit
#endif
#if canImport(NearbyInteraction) && (os(iOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
import NearbyInteraction
#endif
#if canImport(CoreBluetooth) && (os(iOS) || os(macOS) || os(watchOS) || os(tvOS))
import CoreBluetooth
#endif
#if os(macOS)
import Security
#endif

/// Reads capability facts from this device's frameworks without prompting.
///
/// Every call here is a status or support query. None creates a capture session, recognizer
/// task, Bluetooth manager, NISession, or network connection, which are what trigger prompts.
public struct LiveCapabilitySource: CapabilitySource {
    public init() {}

    public var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// The probes this platform's build actually compiled. Tests compare it with the plan in
    /// `Capability.probedPlatforms`, so the two cannot drift apart unnoticed.
    public static var compiledProbes: Set<Capability> {
        var compiled: Set<Capability> = []
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        compiled.formUnion([.camera, .microphone])
        #endif
        #if canImport(AVFAudio) && os(watchOS)
        compiled.insert(.microphone)
        #endif
        #if canImport(Speech) && (os(iOS) || os(macOS))
        compiled.insert(.speechRecognition)
        #endif
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        compiled.insert(.onDeviceLanguageModel)
        #endif
        #if canImport(ARKit) && os(iOS) && !targetEnvironment(macCatalyst)
        compiled.formUnion([.worldTracking, .sceneReconstruction])
        #endif
        #if canImport(NearbyInteraction) && (os(iOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
        compiled.insert(.ultraWideband)
        #endif
        #if canImport(CoreBluetooth) && (os(iOS) || os(macOS) || os(watchOS) || os(tvOS))
        compiled.insert(.bluetooth)
        #endif
        #if os(iOS) || os(macOS) || os(tvOS)
        compiled.insert(.localNetwork) // Reads no framework symbol: the permission is not queryable.
        #endif
        return compiled
    }

    public func permissionStatus(_ permission: PermissionKind) -> PermissionStatus {
        switch permission {
        case .camera:
            #if canImport(AVFoundation) && (os(iOS) || os(macOS))
            return Self.status(AVCaptureDevice.authorizationStatus(for: .video))
            #else
            return .notReadable
            #endif
        case .microphone:
            #if canImport(AVFoundation) && (os(iOS) || os(macOS))
            return Self.status(AVCaptureDevice.authorizationStatus(for: .audio))
            #elseif canImport(AVFAudio) && os(watchOS)
            return Self.status(AVAudioApplication.shared.recordPermission)
            #else
            return .notReadable
            #endif
        case .speechRecognition:
            #if canImport(Speech) && (os(iOS) || os(macOS))
            return Self.status(SFSpeechRecognizer.authorizationStatus())
            #else
            return .notReadable
            #endif
        case .bluetooth:
            #if canImport(CoreBluetooth) && (os(iOS) || os(macOS) || os(watchOS) || os(tvOS))
            // The class property reads status without allocating a manager, so it never prompts.
            return Self.status(CBManager.authorization)
            #else
            return .notReadable
            #endif
        case .nearbyInteraction, .localNetwork:
            return .notReadable
        }
    }

    public func hasCaptureDevice(_ kind: CaptureDeviceKind) -> Bool? {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        // Device discovery does not prompt; only opening an input does.
        return switch kind {
        case .video: AVCaptureDevice.default(for: .video) != nil
        case .audio: AVCaptureDevice.default(for: .audio) != nil
        }
        #elseif canImport(AVFAudio) && os(watchOS)
        return kind == .audio ? AVAudioSession.sharedInstance().isInputAvailable : nil
        #else
        return nil
        #endif
    }

    public func speechTranscription() async -> SpeechTranscriptionReading {
        let locale = Locale.current
        #if canImport(Speech) && (os(iOS) || os(macOS))
        guard SpeechTranscriber.isAvailable else {
            return SpeechTranscriptionReading(
                transcriberAvailable: false, localeIdentifier: locale.identifier, asset: .unknown)
        }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return SpeechTranscriptionReading(
                transcriberAvailable: true, localeIdentifier: locale.identifier, asset: .unsupportedLocale)
        }
        let installed = await SpeechTranscriber.installedLocales
        let isInstalled = installed.contains { $0.identifier(.bcp47) == supported.identifier(.bcp47) }
        return SpeechTranscriptionReading(
            transcriberAvailable: true,
            localeIdentifier: supported.identifier,
            asset: isInstalled ? .installed : .downloadable
        )
        #else
        return SpeechTranscriptionReading(
            transcriberAvailable: nil, localeIdentifier: locale.identifier, asset: .unknown)
        #endif
    }

    public func languageModel() -> LanguageModelReading {
        let locale = Locale.current
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        let model = SystemLanguageModel.default
        let availability: LanguageModelReading.Availability = switch model.availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady): .modelNotReady
        case .unavailable(let reason): .unrecognized(String(describing: reason))
        }
        let readsLocale = availability == .available || availability == .modelNotReady
        return LanguageModelReading(
            availability: availability,
            supportsCurrentLocale: readsLocale ? model.supportsLocale(locale) : nil,
            localeIdentifier: locale.identifier
        )
        #else
        return LanguageModelReading(
            availability: .notCompiled, supportsCurrentLocale: nil, localeIdentifier: locale.identifier)
        #endif
    }

    public func worldTracking() -> WorldTrackingReading? {
        #if canImport(ARKit) && os(iOS) && !targetEnvironment(macCatalyst)
        return WorldTrackingReading(
            worldTracking: ARWorldTrackingConfiguration.isSupported,
            sceneReconstruction: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        )
        #else
        return nil
        #endif
    }

    public func ultraWideband() -> UltraWidebandReading? {
        #if canImport(NearbyInteraction) && (os(iOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
        let capabilities = NISession.deviceCapabilities
        return UltraWidebandReading(
            preciseDistance: capabilities.supportsPreciseDistanceMeasurement,
            direction: capabilities.supportsDirectionMeasurement
        )
        #else
        return nil
        #endif
    }

    public func entitlement(_ key: String) -> EntitlementReading {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return .notReadable }
        guard let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) else { return .absent }
        if let flag = value as? Bool { return flag ? .present : .absent }
        return .present
        #else
        return .notReadable
        #endif
    }

    public func declaresPurposeString(_ key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Status mapping

extension LiveCapabilitySource {
    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    static func status(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unrecognized
        }
    }
    #endif

    #if canImport(AVFAudio) && os(watchOS)
    static func status(_ permission: AVAudioApplication.recordPermission) -> PermissionStatus {
        switch permission {
        case .undetermined: .notDetermined
        case .granted: .authorized
        case .denied: .denied
        @unknown default: .unrecognized
        }
    }
    #endif

    #if canImport(Speech) && (os(iOS) || os(macOS))
    static func status(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unrecognized
        }
    }
    #endif

    #if canImport(CoreBluetooth) && (os(iOS) || os(macOS) || os(watchOS) || os(tvOS))
    static func status(_ authorization: CBManagerAuthorization) -> PermissionStatus {
        switch authorization {
        case .notDetermined: .notDetermined
        case .allowedAlways: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unrecognized
        }
    }
    #endif
}
