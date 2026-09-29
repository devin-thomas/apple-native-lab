import Foundation

#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import AVFoundation
#endif
#if canImport(AVFAudio) && os(watchOS)
import AVFAudio
#endif
#if canImport(Speech) && (os(iOS) || os(macOS))
import Speech
#endif

/// Shows the real system prompt. Only `PermissionStager` calls this, after checking the status,
/// the purpose string, and any required Mac entitlement.
public struct LivePermissionRequester: PermissionRequesting {
    public init() {}

    public func request(_ permission: PermissionKind) async -> PermissionStatus {
        let source = LiveCapabilitySource()
        switch permission {
        case .camera:
            #if canImport(AVFoundation) && (os(iOS) || os(macOS))
            _ = await AVCaptureDevice.requestAccess(for: .video)
            #endif
        case .microphone:
            #if canImport(AVFoundation) && (os(iOS) || os(macOS))
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            #elseif canImport(AVFAudio) && os(watchOS)
            _ = await AVAudioApplication.requestRecordPermission()
            #endif
        case .speechRecognition:
            #if canImport(Speech) && (os(iOS) || os(macOS))
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: LiveCapabilitySource.status(status))
                }
            }
            #endif
        case .bluetooth, .nearbyInteraction, .localNetwork:
            // Not directly requestable: the system asks when the feature starts its session.
            break
        }
        return source.permissionStatus(permission)
    }
}
