import Foundation

/// How a check exercised the code (docs/TEST_STRATEGY.md).
public enum ExecutionPath: String, Codable, Sendable, CaseIterable {
    /// On real hardware: a physical iPhone, Watch, Mac, or other device.
    case physical
    /// In a simulator. Sensor, radio, and entitlement behavior is simulated or absent.
    case simulator
    /// Against deterministic fixtures, such as a unit test with fakes, on any host.
    case fixture
    /// By inspection, without running the code under test.
    case staticReview = "static-review"

    public var title: String {
        switch self {
        case .physical: "Physical device"
        case .simulator: "Simulator"
        case .fixture: "Fixture"
        case .staticReview: "Static review"
        }
    }

    /// The highest implementation state a passing check on this path can support (SPEC §7).
    ///
    /// Only a physical run reaches `device-verified`. A simulator or fixture run can establish
    /// `implemented` for a fallback, and a static review at most `spiked`. No path reaches
    /// `release-ready`: that also needs acceptance, privacy, and accessibility review.
    public var highestSupportedState: ImplementationState {
        switch self {
        case .physical: .deviceVerified
        case .simulator, .fixture: .implemented
        case .staticReview: .spiked
        }
    }
}

/// Where a check ran, with the device facts its path requires.
///
/// The physical case is the only one that carries a `PhysicalDevice`, and decoding refuses
/// device fields on any other path, so a simulator or fixture record cannot describe itself as
/// running on hardware.
public enum Execution: Sendable, Equatable {
    case physical(PhysicalDevice)
    case simulator(SimulatedDevice)
    case fixture
    case staticReview

    public var path: ExecutionPath {
        switch self {
        case .physical: .physical
        case .simulator: .simulator
        case .fixture: .fixture
        case .staticReview: .staticReview
        }
    }

    /// The execution a live run on `snapshot`'s device represents. A simulator snapshot always
    /// gives the simulator path.
    public init(observing snapshot: DeviceSnapshot) throws {
        guard let platform = LabPlatform(rawValue: snapshot.platform) else {
            throw EvidenceError.unknownPlatform(snapshot.platform)
        }
        switch snapshot.environment {
        case .physical:
            self = .physical(try PhysicalDevice(
                platform: platform, deviceClass: snapshot.modelIdentifier, osVersion: snapshot.osVersion
            ))
        case .simulator:
            self = .simulator(SimulatedDevice(
                platform: platform, deviceClass: snapshot.modelIdentifier, osVersion: snapshot.osVersion
            ))
        }
    }

    /// A short description for logs, such as "Physical device, iPhone17,1, iOS 27.0".
    public var summary: String {
        switch self {
        case .physical(let device):
            "\(path.title), \(device.deviceClass), \(device.platform.title) \(device.osVersion)"
        case .simulator(let device):
            [path.title, device.deviceClass, device.osVersion.map { "\(device.platform.title) \($0)" }]
                .compactMap { $0 }
                .joined(separator: ", ")
        case .fixture, .staticReview:
            path.title
        }
    }
}

extension Execution: Codable {
    private enum CodingKeys: String, CodingKey {
        case path
        case device
        case simulator
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(ExecutionPath.self, forKey: .path)
        if path != .physical, container.contains(.device) {
            throw DecodingError.dataCorruptedError(
                forKey: .device, in: container,
                debugDescription: "Only the physical path can name a physical device; this record's path is \(path.rawValue)."
            )
        }
        if path != .simulator, container.contains(.simulator) {
            throw DecodingError.dataCorruptedError(
                forKey: .simulator, in: container,
                debugDescription: "Only the simulator path can name a simulator; this record's path is \(path.rawValue)."
            )
        }
        switch path {
        case .physical: self = .physical(try container.decode(PhysicalDevice.self, forKey: .device))
        case .simulator: self = .simulator(try container.decode(SimulatedDevice.self, forKey: .simulator))
        case .fixture: self = .fixture
        case .staticReview: self = .staticReview
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        switch self {
        case .physical(let device): try container.encode(device, forKey: .device)
        case .simulator(let device): try container.encode(device, forKey: .simulator)
        case .fixture, .staticReview: break
        }
    }
}

/// The hardware a physical run used, described by class and OS only.
///
/// It never holds a serial number, device identifier, or account identifier: the initializer
/// refuses values that look like one (docs/SECURITY_AND_PRIVACY.md).
public struct PhysicalDevice: Sendable, Equatable {
    public let platform: LabPlatform
    /// The hardware model, such as "iPhone17,1 (iPhone 16 Pro)" or "Mac16,5".
    public let deviceClass: String
    /// The OS version and build, such as "27.0 (24A5430a)".
    public let osVersion: String
    /// When the provisioning profile of a development-signed install expires, if one was used.
    public let profileExpiry: Date?

    public init(platform: LabPlatform, deviceClass: String, osVersion: String, profileExpiry: Date? = nil) throws {
        guard !deviceClass.isBlank else { throw EvidenceError.blankField("device.deviceClass") }
        guard !osVersion.isBlank else { throw EvidenceError.blankField("device.osVersion") }
        guard !DeviceIdentifierScreen.containsIdentifier(deviceClass) else {
            throw EvidenceError.deviceIdentifier(field: "device.deviceClass")
        }
        guard !DeviceIdentifierScreen.containsIdentifier(osVersion) else {
            throw EvidenceError.deviceIdentifier(field: "device.osVersion")
        }
        self.platform = platform
        self.deviceClass = deviceClass
        self.osVersion = osVersion
        self.profileExpiry = profileExpiry.map(EvidenceDate.normalized)
    }
}

extension PhysicalDevice: Codable {
    private enum CodingKeys: String, CodingKey {
        case platform
        case deviceClass
        case osVersion
        case profileExpiry
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let expiry = try container.decodeIfPresent(String.self, forKey: .profileExpiry).map { text in
            guard let date = EvidenceDate.parse(text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .profileExpiry, in: container, debugDescription: "Expected an ISO 8601 date."
                )
            }
            return date
        }
        do {
            try self.init(
                platform: try container.decode(LabPlatform.self, forKey: .platform),
                deviceClass: try container.decode(String.self, forKey: .deviceClass),
                osVersion: try container.decode(String.self, forKey: .osVersion),
                profileExpiry: expiry
            )
        } catch let error as EvidenceError {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: error.description))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(platform, forKey: .platform)
        try container.encode(deviceClass, forKey: .deviceClass)
        try container.encode(osVersion, forKey: .osVersion)
        try container.encodeIfPresent(profileExpiry.map(EvidenceDate.format), forKey: .profileExpiry)
    }
}

/// The simulator a simulator run used. Device class and runtime are absent for a build against a
/// generic simulator destination.
public struct SimulatedDevice: Sendable, Equatable, Codable {
    public let platform: LabPlatform
    /// The simulated model, such as "iPhone 17".
    public let deviceClass: String?
    /// The simulator runtime version, such as "27.0".
    public let osVersion: String?

    public init(platform: LabPlatform, deviceClass: String? = nil, osVersion: String? = nil) {
        self.platform = platform
        self.deviceClass = deviceClass.flatMap { $0.isBlank ? nil : $0 }
        self.osVersion = osVersion.flatMap { $0.isBlank ? nil : $0 }
    }
}

/// Screens device descriptions for values that identify one device or account.
enum DeviceIdentifierScreen {
    static func containsIdentifier(_ value: String) -> Bool {
        let separators = CharacterSet(charactersIn: " \t()[]{},;:/=")
        return value.components(separatedBy: separators).contains { token in
            !token.isEmpty && (isUUID(token) || isHardwareUDID(token) || isSerialNumber(token))
        }
    }

    private static func isUUID(_ token: String) -> Bool {
        UUID(uuidString: token) != nil
    }

    /// Hardware UDIDs are 24 or 40 hexadecimal digits, sometimes split by one hyphen.
    private static func isHardwareUDID(_ token: String) -> Bool {
        let digits = token.filter { $0 != "-" }
        return digits.count >= 24 && digits.allSatisfy(\.isHexDigit)
    }

    /// Apple serial numbers are 10 to 12 uppercase letters and digits, mixing both.
    private static func isSerialNumber(_ token: String) -> Bool {
        guard (10...12).contains(token.count),
              token.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { return false }
        return token.filter(\.isNumber).count >= 2 && token.filter(\.isLetter).count >= 2
    }
}
