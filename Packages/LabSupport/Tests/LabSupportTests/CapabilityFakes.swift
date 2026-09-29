import Foundation
import Synchronization
@testable import LabSupport

/// A deterministic device. Defaults describe a fully capable, fully configured device whose
/// permissions have not been asked yet.
struct FakeCapabilitySource: CapabilitySource {
    var isSimulator = false
    var statuses: [PermissionKind: PermissionStatus] = [:]
    var captureDevices: [CaptureDeviceKind: Bool] = [.video: true, .audio: true]
    var speech = SpeechTranscriptionReading(transcriberAvailable: true, localeIdentifier: "en_US", asset: .installed)
    var model = LanguageModelReading(availability: .available, supportsCurrentLocale: true, localeIdentifier: "en_US")
    var arkit: WorldTrackingReading? = WorldTrackingReading(worldTracking: true, sceneReconstruction: true)
    var uwb: UltraWidebandReading? = UltraWidebandReading(preciseDistance: true, direction: true)
    var entitlements: [String: EntitlementReading] = [:]
    var defaultEntitlement: EntitlementReading = .present
    var purposeStrings: Set<String> = Set(PermissionKind.allCases.compactMap(\.purposeStringKey))

    func permissionStatus(_ permission: PermissionKind) -> PermissionStatus {
        if permission.unreadableReason != nil { return .notReadable }
        return statuses[permission] ?? .notDetermined
    }
    func hasCaptureDevice(_ kind: CaptureDeviceKind) -> Bool? { captureDevices[kind] }
    func speechTranscription() async -> SpeechTranscriptionReading { speech }
    func languageModel() -> LanguageModelReading { model }
    func worldTracking() -> WorldTrackingReading? { arkit }
    func ultraWideband() -> UltraWidebandReading? { uwb }
    func entitlement(_ key: String) -> EntitlementReading { entitlements[key] ?? defaultEntitlement }
    func declaresPurposeString(_ key: String) -> Bool { purposeStrings.contains(key) }
}

/// Records every prompt. `answers` decides what the person taps; the delay lets tests overlap
/// requests to prove they share one prompt.
final class SpyRequester: PermissionRequesting {
    private let log = Mutex<[PermissionKind]>([])
    let answers: [PermissionKind: PermissionStatus]
    let delay: Duration

    init(answers: [PermissionKind: PermissionStatus] = [:], delay: Duration = .zero) {
        self.answers = answers
        self.delay = delay
    }

    var requests: [PermissionKind] { log.withLock { $0 } }

    func request(_ permission: PermissionKind) async -> PermissionStatus {
        log.withLock { $0.append(permission) }
        if delay > .zero { try? await Task.sleep(for: delay) }
        return answers[permission] ?? .authorized
    }
}

/// A source that is also a requester, to prove the registry never reaches for a prompt even
/// when one is within reach of the object it was given.
final class PromptTrapSource: CapabilitySource, PermissionRequesting {
    let base: FakeCapabilitySource
    let spy = SpyRequester()

    init(base: FakeCapabilitySource = FakeCapabilitySource()) { self.base = base }

    var isSimulator: Bool { base.isSimulator }
    func permissionStatus(_ permission: PermissionKind) -> PermissionStatus { base.permissionStatus(permission) }
    func hasCaptureDevice(_ kind: CaptureDeviceKind) -> Bool? { base.hasCaptureDevice(kind) }
    func speechTranscription() async -> SpeechTranscriptionReading { await base.speechTranscription() }
    func languageModel() -> LanguageModelReading { base.languageModel() }
    func worldTracking() -> WorldTrackingReading? { base.worldTracking() }
    func ultraWideband() -> UltraWidebandReading? { base.ultraWideband() }
    func entitlement(_ key: String) -> EntitlementReading { base.entitlement(key) }
    func declaresPurposeString(_ key: String) -> Bool { base.declaresPurposeString(key) }
    func request(_ permission: PermissionKind) async -> PermissionStatus { await spy.request(permission) }
}

func action(_ capability: Capability) -> FeatureAction {
    FeatureAction(capability: capability, experimentID: "LAB-000", title: "Test action")
}
