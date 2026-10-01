import Foundation

/// One MIDI channel voice message, from a MIDI 1.0 byte stream, a Universal MIDI Packet, or the
/// on-screen controls. Channels are numbered 1 to 16, as people read them.
public enum MidiEvent: Hashable, Sendable {
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8)
    /// Any other channel voice message, kept only so the log can say something arrived.
    case other(channel: UInt8, status: UInt8)

    public var channel: UInt8 {
        switch self {
        case .controlChange(let channel, _, _), .noteOn(let channel, _, _), .noteOff(let channel, _, _),
             .other(let channel, _):
            channel
        }
    }

    public var description: String {
        switch self {
        case .controlChange(let channel, let controller, let value): "CC \(controller) = \(value), channel \(channel)"
        case .noteOn(let channel, let note, let velocity): "Note on \(note), velocity \(velocity), channel \(channel)"
        case .noteOff(let channel, let note, _): "Note off \(note), channel \(channel)"
        case .other(let channel, let status): "Message \(String(format: "0x%02X", status)), channel \(channel)"
        }
    }

    /// The MIDI 1.0 bytes of the message; the on-screen controls send exactly these.
    public var bytes: [UInt8] {
        let index = (channel &- 1) & 0x0F
        switch self {
        case .controlChange(_, let controller, let value): return [0xB0 | index, controller & 0x7F, value & 0x7F]
        case .noteOn(_, let note, let velocity): return [0x90 | index, note & 0x7F, velocity & 0x7F]
        case .noteOff(_, let note, let velocity): return [0x80 | index, note & 0x7F, velocity & 0x7F]
        case .other(_, let status): return [status]
        }
    }
}

/// Reads MIDI 1.0 bytes, with running status. System messages are skipped: real-time bytes may
/// appear anywhere, and a System Exclusive message is skipped up to its end.
public struct MidiByteParser: Sendable {
    private var status: UInt8?
    private var data: [UInt8] = []
    private var inSystemExclusive = false

    public init() {}

    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [MidiEvent] {
        var events: [MidiEvent] = []
        for byte in bytes {
            if byte >= 0xF8 { continue } // real-time: never interrupts running status
            if inSystemExclusive {
                if byte == 0xF7 { inSystemExclusive = false }
                if byte < 0x80 || byte == 0xF7 { continue }
                inSystemExclusive = false // any other status byte ends it
            }
            if byte >= 0xF0 {
                // System common cancels running status.
                status = nil
                data.removeAll()
                inSystemExclusive = byte == 0xF0
                continue
            }
            if byte >= 0x80 {
                status = byte
                data.removeAll()
                continue
            }
            guard let status else { continue } // data with no status is dropped
            data.append(byte)
            let kind = status & 0xF0
            let needed = kind == 0xC0 || kind == 0xD0 ? 1 : 2
            if data.count == needed {
                events.append(Self.event(status: status, data: data))
                data.removeAll()
            }
        }
        return events
    }

    static func event(status: UInt8, data: [UInt8]) -> MidiEvent {
        let channel = (status & 0x0F) + 1
        switch status & 0xF0 {
        case 0xB0: return .controlChange(channel: channel, controller: data[0], value: data[1])
        // A note on with velocity 0 is a note off, by the MIDI 1.0 convention.
        case 0x90 where data[1] == 0: return .noteOff(channel: channel, note: data[0], velocity: 0)
        case 0x90: return .noteOn(channel: channel, note: data[0], velocity: data[1])
        case 0x80: return .noteOff(channel: channel, note: data[0], velocity: data[1])
        default: return .other(channel: channel, status: status & 0xF0)
        }
    }
}

/// Reads channel voice messages from Universal MIDI Packets, as Core MIDI delivers them: MIDI 1.0
/// messages (type 2, one word) and MIDI 2.0 messages (type 4, two words, whose 32-bit controller
/// values are reduced to 7 bits). Other packet types are skipped by their length.
public enum UniversalMidi {
    public static func events(from words: some Collection<UInt32>) -> [MidiEvent] {
        var events: [MidiEvent] = []
        var index = words.startIndex
        while index != words.endIndex {
            let first = words[index]
            let type = UInt8(first >> 28)
            let length = wordCount(type)
            guard words.distance(from: index, to: words.endIndex) >= length else { break }
            let status = UInt8((first >> 16) & 0xFF)
            let channel = (status & 0x0F) + 1
            if type == 0x2 {
                let data = [UInt8((first >> 8) & 0x7F), UInt8(first & 0x7F)]
                events.append(MidiByteParser.event(status: status, data: data))
            } else if type == 0x4 {
                let second = words[words.index(after: index)]
                let first7 = UInt8((first >> 8) & 0x7F)
                switch status & 0xF0 {
                case 0xB0:
                    events.append(.controlChange(channel: channel, controller: first7, value: UInt8(second >> 25)))
                case 0x90:
                    let velocity = UInt8(second >> 25)
                    events.append(.noteOn(channel: channel, note: first7, velocity: max(velocity, 1)))
                case 0x80:
                    events.append(.noteOff(channel: channel, note: first7, velocity: UInt8(second >> 25)))
                default:
                    events.append(.other(channel: channel, status: status & 0xF0))
                }
            }
            index = words.index(index, offsetBy: length)
        }
        return events
    }

    /// Words per packet by message type, from the UMP format.
    static func wordCount(_ type: UInt8) -> Int {
        switch type {
        case 0x0, 0x1, 0x2, 0x6, 0x7: 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: 2
        case 0xB, 0xC: 3
        default: 4
        }
    }
}

/// The one mapped MIDI parameter: a controller moves the filter cutoff along an exponential
/// curve, so each step of the controller is the same musical interval.
public struct MidiMapping: Hashable, Sendable {
    /// CC 74, the controller conventionally used for brightness, from 80 Hz to 12 kHz on any channel.
    public static let standard = MidiMapping(uncheckedController: 74, channel: nil, lowHertz: 80, highHertz: 12_000)

    public let controller: UInt8
    /// 1 to 16, or `nil` for any channel.
    public let channel: UInt8?
    public let lowHertz: Double
    public let highHertz: Double

    /// Controllers 120 to 127 are channel mode messages, not controllers, so they cannot be mapped.
    public static let controllers: ClosedRange<UInt8> = 0...119

    public init(controller: UInt8, channel: UInt8? = nil, lowHertz: Double = 80, highHertz: Double = 12_000) throws(PresetRejection) {
        guard Self.controllers.contains(controller) else { throw .outOfRange("midi.controller") }
        if let channel { guard (1...16).contains(channel) else { throw .outOfRange("midi.channel") } }
        let range = WorkshopParameter.cutoffHertz.range
        guard lowHertz.isFinite, highHertz.isFinite, range.contains(lowHertz), range.contains(highHertz),
              lowHertz < highHertz else { throw .outOfRange("midi.range") }
        self.init(uncheckedController: controller, channel: channel, lowHertz: lowHertz, highHertz: highHertz)
    }

    private init(uncheckedController controller: UInt8, channel: UInt8?, lowHertz: Double, highHertz: Double) {
        self.controller = controller
        self.channel = channel
        self.lowHertz = lowHertz
        self.highHertz = highHertz
    }

    /// The cutoff a controller value asks for.
    public func cutoff(forValue value: UInt8) -> Double {
        let position = Double(min(value, 127)) / 127
        return lowHertz * pow(highHertz / lowHertz, position)
    }

    /// The controller value nearest a cutoff, for showing where the controller would sit.
    public func value(forCutoff hertz: Double) -> UInt8 {
        let clamped = min(max(hertz, lowHertz), highHertz)
        let position = log(clamped / lowHertz) / log(highHertz / lowHertz)
        return UInt8((position * 127).rounded())
    }

    /// The cutoff an event asks for, or `nil` when the event is not this mapping's controller.
    public func cutoff(for event: MidiEvent) -> Double? {
        guard case .controlChange(let eventChannel, let eventController, let value) = event,
              eventController == controller, channel == nil || channel == eventChannel else { return nil }
        return cutoff(forValue: value)
    }

    public var summary: String {
        let where_ = channel.map { "channel \($0)" } ?? "any channel"
        return "CC \(controller) on \(where_) sets the cutoff, \(AudioGraphPreset.hertzText(lowHertz)) to \(AudioGraphPreset.hertzText(highHertz))"
    }

    public func with(controller: UInt8) -> MidiMapping {
        MidiMapping(uncheckedController: min(controller, Self.controllers.upperBound), channel: channel,
                    lowHertz: lowHertz, highHertz: highHertz)
    }

    // MARK: Stored form, inside a preset

    private enum Field: String, CaseIterable {
        case controller, channel, lowHertz, highHertz
    }

    var jsonObject: [String: Any] {
        [
            Field.controller.rawValue: Int(controller),
            // JSON null for any channel, so the field is always present.
            Field.channel.rawValue: channel.map { Int($0) as Any } ?? NSNull(),
            Field.lowHertz.rawValue: lowHertz,
            Field.highHertz.rawValue: highHertz,
        ]
    }

    init(object: [String: Any]) throws(PresetRejection) {
        if let unknown = object.keys.sorted().first(where: { Field(rawValue: $0) == nil }) { throw .unknownField("midi.\(unknown)") }
        let controller = try AudioGraphPreset.integer(object, Field.controller.rawValue)
        guard (0...127).contains(controller) else { throw .outOfRange("midi.controller") }
        guard let rawChannel = object[Field.channel.rawValue] else { throw .missingField("midi.channel") }
        var channel: UInt8?
        if !(rawChannel is NSNull) {
            let value = try AudioGraphPreset.integer(object, Field.channel.rawValue)
            guard (1...16).contains(value) else { throw .outOfRange("midi.channel") }
            channel = UInt8(value)
        }
        try self.init(
            controller: UInt8(controller), channel: channel,
            lowHertz: AudioGraphPreset.number(object, Field.lowHertz.rawValue),
            highHertz: AudioGraphPreset.number(object, Field.highHertz.rawValue)
        )
    }
}
