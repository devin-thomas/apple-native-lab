import Foundation

/// What one device has seen of a record, as a counter per device.
///
/// A vector that is greater in every component, and strictly greater in one, happened after the
/// other: that edit saw the earlier one. When neither happened after the other, the edits were
/// made apart and both stay inspectable. Equality is the same edit, not a conflict.
public struct VersionVector: Hashable, Sendable, Codable {
    public private(set) var counters: [DeviceID: UInt64]

    public static let empty = VersionVector(counters: [:])

    public init(counters: [DeviceID: UInt64] = [:]) {
        self.counters = counters.filter { $0.value > 0 }
    }

    /// The vector after this device makes one more edit.
    public func incrementing(_ device: DeviceID) -> VersionVector {
        var copy = counters
        copy[device, default: 0] += 1
        return VersionVector(counters: copy)
    }

    /// The least vector that happened after both, before the next local edit increments it.
    public func merging(_ other: VersionVector) -> VersionVector {
        var copy = counters
        for (device, count) in other.counters {
            copy[device] = max(copy[device] ?? 0, count)
        }
        return VersionVector(counters: copy)
    }

    /// True when this edit saw `other`: every counter is at least as large, and one is larger.
    public func happenedAfter(_ other: VersionVector) -> Bool {
        let devices = Set(counters.keys).union(other.counters.keys)
        var strictlyGreater = false
        for device in devices {
            let mine = counters[device] ?? 0
            let theirs = other.counters[device] ?? 0
            if mine < theirs { return false }
            if mine > theirs { strictlyGreater = true }
        }
        return strictlyGreater
    }

    public func concurrent(with other: VersionVector) -> Bool {
        self != other && !happenedAfter(other) && !other.happenedAfter(self)
    }

    private struct Pair: Codable {
        var device: DeviceID
        var count: UInt64
    }

    private enum CodingKeys: String, CodingKey { case counters }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pairs = try container.decode([Pair].self, forKey: .counters)
        var counters: [DeviceID: UInt64] = [:]
        for pair in pairs {
            guard pair.count > 0, counters[pair.device] == nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .counters, in: container, debugDescription: "A version vector repeats a device or has an empty count."
                )
            }
            counters[pair.device] = pair.count
        }
        self.init(counters: counters)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let pairs = counters
            .map { Pair(device: $0.key, count: $0.value) }
            .sorted { $0.device.rawValue.uuidString < $1.device.rawValue.uuidString }
        try container.encode(pairs, forKey: .counters)
    }
}
