import Foundation

/// A deliberately small description of the device running the lab.
///
/// It records the platform, OS, hardware model, and coarse resources. It never reads serial
/// numbers, account identifiers, names, or location (docs/SECURITY_AND_PRIVACY.md).
public struct DeviceSnapshot: Sendable, Equatable {
    public enum Environment: String, Sendable {
        case physical
        case simulator
    }

    public var platform: String
    public var osVersion: String
    public var modelIdentifier: String
    public var environment: Environment
    public var memoryGigabytes: Int
    public var processorCount: Int

    public init(
        platform: String,
        osVersion: String,
        modelIdentifier: String,
        environment: Environment,
        memoryGigabytes: Int,
        processorCount: Int
    ) {
        self.platform = platform
        self.osVersion = osVersion
        self.modelIdentifier = modelIdentifier
        self.environment = environment
        self.memoryGigabytes = memoryGigabytes
        self.processorCount = processorCount
    }

    public static var current: DeviceSnapshot {
        let process = ProcessInfo.processInfo
        #if targetEnvironment(simulator)
        let environment = Environment.simulator
        let model = process.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "simulator"
        #else
        let environment = Environment.physical
        let model = hardwareModel()
        #endif
        let gigabyte = Double(1 << 30)
        return DeviceSnapshot(
            platform: platformName,
            osVersion: process.operatingSystemVersionString,
            modelIdentifier: model,
            environment: environment,
            memoryGigabytes: Int((Double(process.physicalMemory) / gigabyte).rounded()),
            processorCount: process.processorCount
        )
    }

    private static var platformName: String {
        #if os(macOS)
        "macOS"
        #elseif os(watchOS)
        "watchOS"
        #elseif os(tvOS)
        "tvOS"
        #elseif os(visionOS)
        "visionOS"
        #elseif os(iOS)
        "iOS"
        #else
        "unknown"
        #endif
    }

    private static func hardwareModel() -> String {
        #if os(macOS)
        let key = "hw.model"
        #else
        let key = "hw.machine"
        #endif
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
