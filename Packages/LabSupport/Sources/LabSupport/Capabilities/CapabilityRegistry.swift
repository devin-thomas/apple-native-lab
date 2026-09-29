/// Runs the no-prompt probes this platform compiles and explains the ones it leaves out.
///
/// The registry holds only a read-only `CapabilitySource`, so it has no way to ask for a
/// permission. Launch and the Readiness screen can call it freely.
public struct CapabilityRegistry: Sendable {
    public let platform: LabPlatform
    private let source: any CapabilitySource

    public init(platform: LabPlatform = .current, source: any CapabilitySource) {
        self.platform = platform
        self.source = source
    }

    /// The registry backed by this device's frameworks.
    public static func live() -> CapabilityRegistry {
        CapabilityRegistry(platform: .current, source: LiveCapabilitySource())
    }

    /// Capabilities this platform's build probes, in display order.
    public var probed: [Capability] { Capability.probed(on: platform) }

    /// Capabilities this platform's build leaves out entirely.
    public var excluded: [Capability] { Capability.excluded(on: platform) }

    /// Probes one capability. An excluded capability is reported from static facts without
    /// touching the source.
    public func report(for capability: Capability) async -> CapabilityReport {
        guard capability.probedPlatforms.contains(platform) else {
            return Self.excludedReport(for: capability, on: platform)
        }
        let gates = await CapabilityProbes.gates(for: capability, on: platform, source: source)
        return CapabilityReport(capability: capability, platform: platform, gates: gates, isProbed: true)
    }

    /// Probes every capability this platform compiles, concurrently, in display order.
    public func probeAll() async -> [CapabilityReport] {
        let reports = await withTaskGroup(of: CapabilityReport.self) { group in
            for capability in probed {
                group.addTask { await report(for: capability) }
            }
            var reports: [CapabilityReport] = []
            for await report in group { reports.append(report) }
            return reports
        }
        let order = Capability.allCases
        return reports.sorted { order.firstIndex(of: $0.capability)! < order.firstIndex(of: $1.capability)! }
    }

    /// Static reports for the capabilities this platform leaves out.
    public func excludedReports() -> [CapabilityReport] {
        excluded.map { Self.excludedReport(for: $0, on: platform) }
    }

    static func excludedReport(for capability: Capability, on platform: LabPlatform) -> CapabilityReport {
        let gates = [
            CapabilityGate(.osAPI, .unmet, capability.exclusionNote(on: platform)),
            .noDeviceEvidence,
        ]
        return CapabilityReport(capability: capability, platform: platform, gates: gates, isProbed: false)
    }
}

extension Capability {
    /// Why a platform's build has no probe for this capability. Each statement was checked
    /// against the availability annotations in the 27.0 SDKs.
    func exclusionNote(on platform: LabPlatform) -> String {
        let reason: String = switch (self, platform) {
        case (_, .visionOS):
            "visionOS is outside the initial plan."
        case (.camera, .watchOS):
            "AVCaptureDevice is unavailable on watchOS."
        case (.camera, _), (.microphone, _):
            "The \(platform.title) host is not part of the plan yet."
        case (.speechRecognition, .watchOS):
            "The watchOS SDK has no Speech framework."
        case (.speechRecognition, _):
            "SFSpeechRecognizer is unavailable on \(platform.title)."
        case (.onDeviceLanguageModel, _):
            "SystemLanguageModel is marked unavailable on \(platform.title)."
        case (.worldTracking, .macOS), (.sceneReconstruction, .macOS):
            "ARWorldTrackingConfiguration is iOS-only; the macOS ARKit module is a different API."
        case (.worldTracking, _), (.sceneReconstruction, _):
            "The \(platform.title) SDK has no ARKit."
        case (.ultraWideband, _):
            "NISession is marked unavailable on \(platform.title)."
        case (.localNetwork, .watchOS):
            "The Watch reaches local peers through the paired iPhone relay instead."
        case (.bluetooth, _), (.localNetwork, _):
            "No probe is planned for \(platform.title)."
        }
        return "\(reason) This build does not compile its probe."
    }
}
