import Foundation

/// Stable identity for one accessory in a home snapshot. Not a HomeKit UUID.
public struct AccessoryID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init(_ uuid: UUID) { rawValue = uuid }
}

/// Lab-owned service class. Maps to HomeKit service types in the live adapter; the fictional
/// home uses the same names so exclusion rules stay identical on both routes.
public enum AccessoryKind: String, Hashable, Sendable, Codable, CaseIterable {
    case light
    case lock
    case door
    case alarm
    case heating

    public var title: String {
        switch self {
        case .light: "Light"
        case .lock: "Lock"
        case .door: "Door"
        case .alarm: "Alarm"
        case .heating: "Heating"
        }
    }

    /// Locks, doors, alarms, and heating are excluded from scene proposals by default.
    public var isExcludedByDefault: Bool {
        switch self {
        case .light: false
        case .lock, .door, .alarm, .heating: true
        }
    }

    /// The HomeKit `HMServiceType*` constant name this kind corresponds to, for probes and notes.
    public var homeKitServiceTypeSymbol: String {
        switch self {
        case .light: "HMServiceTypeLightbulb"
        case .lock: "HMServiceTypeLockMechanism"
        case .door: "HMServiceTypeDoor"
        case .alarm: "HMServiceTypeSecuritySystem"
        case .heating: "HMServiceTypeThermostat"
        }
    }
}

/// One accessory as the sandbox saw it: kind, reachability, and current light state when relevant.
public struct AccessorySnapshot: Hashable, Sendable, Codable {
    public let id: AccessoryID
    public let name: String
    public let room: String
    public let kind: AccessoryKind
    /// False when the accessory cannot take a write (matches HomeKit `HMAccessory.isReachable`).
    public let isReachable: Bool
    /// Power for lights; `nil` for kinds that are not lights.
    public let isOn: Bool?
    /// Brightness 0…100 for lights that support it; `nil` otherwise.
    public let brightness: Int?

    public init(
        id: AccessoryID,
        name: String,
        room: String,
        kind: AccessoryKind,
        isReachable: Bool,
        isOn: Bool? = nil,
        brightness: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.room = room
        self.kind = kind
        self.isReachable = isReachable
        self.isOn = isOn
        self.brightness = brightness
    }

    public var isExcludedByDefault: Bool { kind.isExcludedByDefault }

    public var statusLine: String {
        if kind == .light {
            let power = (isOn == true) ? "on" : "off"
            if let brightness {
                return "\(name) · \(power) · \(brightness)% · \(isReachable ? "reachable" : "disconnected")"
            }
            return "\(name) · \(power) · \(isReachable ? "reachable" : "disconnected")"
        }
        let exclusion = isExcludedByDefault ? "excluded by default" : "available"
        return "\(name) · \(kind.title) · \(exclusion)"
    }
}

/// A requested change for one light: power and/or brightness.
public struct LightChange: Hashable, Sendable, Codable {
    public let isOn: Bool?
    public let brightness: Int?

    public init(isOn: Bool? = nil, brightness: Int? = nil) {
        self.isOn = isOn
        self.brightness = brightness
    }

    public var isEmpty: Bool { isOn == nil && brightness == nil }

    public var summary: String {
        var parts: [String] = []
        if let isOn { parts.append(isOn ? "on" : "off") }
        if let brightness { parts.append("\(brightness)%") }
        return parts.joined(separator: ", ")
    }
}
