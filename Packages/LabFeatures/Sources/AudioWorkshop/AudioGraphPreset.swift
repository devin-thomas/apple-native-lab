import Foundation
import LabDomain

/// The saved shape of the graph: which loop plays, the gain, the low-pass filter, and the MIDI
/// mapping. Bypass and panic mute are deliberately not part of it. They are session safety
/// controls, so loading a preset can never unmute the output or silently change bypass.
///
/// Every value is checked when a preset is made or decoded. A stored preset outside a range is
/// refused rather than clamped: a preset that could come from another build or another app is
/// data, and quietly changing it would make the saved sound differ from what was saved.
public struct AudioGraphPreset: Hashable, Sendable {
    public static let format = "native-lab-audio-preset"
    public static let schemaVersion = 1

    public private(set) var loop: LoopFixture
    public private(set) var gainDecibels: Double
    public private(set) var filterEnabled: Bool
    public private(set) var cutoffHertz: Double
    public private(set) var resonance: Double
    public private(set) var midi: MidiMapping

    /// The first-run graph: the pulse loop at -6 dB through a 2.4 kHz low-pass.
    public static let standard = AudioGraphPreset(
        uncheckedLoop: .pulse, gainDecibels: -6, filterEnabled: true, cutoffHertz: 2_400, resonance: 0.9, midi: .standard
    )

    public init(
        loop: LoopFixture,
        gainDecibels: Double,
        filterEnabled: Bool,
        cutoffHertz: Double,
        resonance: Double,
        midi: MidiMapping = .standard
    ) throws(PresetRejection) {
        try Self.check(.gainDecibels, gainDecibels)
        try Self.check(.cutoffHertz, cutoffHertz)
        try Self.check(.resonance, resonance)
        self.init(uncheckedLoop: loop, gainDecibels: gainDecibels, filterEnabled: filterEnabled,
                  cutoffHertz: cutoffHertz, resonance: resonance, midi: midi)
    }

    private init(
        uncheckedLoop loop: LoopFixture, gainDecibels: Double, filterEnabled: Bool, cutoffHertz: Double,
        resonance: Double, midi: MidiMapping
    ) {
        self.loop = loop
        self.gainDecibels = gainDecibels
        self.filterEnabled = filterEnabled
        self.cutoffHertz = cutoffHertz
        self.resonance = resonance
        self.midi = midi
    }

    private static func check(_ parameter: WorkshopParameter, _ value: Double) throws(PresetRejection) {
        guard value.isFinite, parameter.range.contains(value) else { throw .outOfRange(parameter.rawValue) }
    }

    // MARK: Editing, as a person moves a control

    /// A value from a control, clamped to its range. A non-finite value changes nothing.
    public mutating func set(_ parameter: WorkshopParameter, to value: Double) {
        guard value.isFinite else { return }
        let kept = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        switch parameter {
        case .gainDecibels: gainDecibels = kept
        case .cutoffHertz: cutoffHertz = kept
        case .resonance: resonance = kept
        case .filterEnabled: filterEnabled = kept >= 0.5
        case .loop: loop = LoopFixture.allCases[Int(kept.rounded())]
        case .bypass, .mute: break
        }
    }

    public mutating func setLoop(_ loop: LoopFixture) { self.loop = loop }
    public mutating func setMidi(_ mapping: MidiMapping) { midi = mapping }

    /// One line for a person: what the preset does.
    public var summary: String {
        let filter = filterEnabled
            ? "low-pass at \(Self.hertzText(cutoffHertz)), Q \(String(format: "%.1f", resonance))"
            : "filter off"
        return "\(loop.title) loop, \(Self.decibelText(gainDecibels)), \(filter). \(midi.summary)."
    }

    public static func decibelText(_ value: Double) -> String {
        String(format: "%+.1f dB", value)
    }

    public static func hertzText(_ value: Double) -> String {
        value >= 1_000 ? String(format: "%.2f kHz", value / 1_000) : String(format: "%.0f Hz", value)
    }
}

/// Why a preset was refused. Each case leaves the current graph unchanged.
public enum PresetRejection: Error, Hashable, Sendable {
    /// Not strict JSON, or not an object, or larger than a preset can be.
    case malformed
    /// JSON, but not an Audio Workshop preset.
    case notAPreset
    /// Made by a newer build; this one does not guess at its meaning.
    case newerVersion(Int)
    case unknownField(String)
    case missingField(String)
    case outOfRange(String)

    public var message: String {
        switch self {
        case .malformed: "This is not a readable preset."
        case .notAPreset: "This item is not an Audio Workshop preset."
        case .newerVersion(let version): "This preset was saved by a newer version (format \(version)). Nothing was loaded."
        case .unknownField(let field): "This preset has a field this version does not know, \(field). Nothing was loaded."
        case .missingField(let field): "This preset is missing \(field). Nothing was loaded."
        case .outOfRange(let field): "This preset's \(field) is outside the range the workshop allows. Nothing was loaded."
        }
    }
}

// MARK: The stored form

extension AudioGraphPreset {
    /// The key the preset lives under in an item's extras, next to anything else the item keeps.
    public static let extrasKey = "audioWorkshopPreset"
    /// A preset is a few hundred bytes; anything much larger is not one.
    public static let maximumBytes = 4 * 1_024

    private enum Field: String, CaseIterable {
        case format, schemaVersion, loop, gainDecibels, filterEnabled, cutoffHertz, resonance, midi
    }

    /// The preset as canonical JSON: sorted keys, no whitespace. The same preset always gives the
    /// same bytes, which the audio unit's saved state and the tests rely on.
    public var canonicalJSON: Data {
        // Every value is a string, number, or Boolean, so encoding cannot fail.
        try! JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    var jsonObject: [String: Any] {
        [
            Field.format.rawValue: Self.format,
            Field.schemaVersion.rawValue: Self.schemaVersion,
            Field.loop.rawValue: loop.rawValue,
            Field.gainDecibels.rawValue: gainDecibels,
            Field.filterEnabled.rawValue: filterEnabled,
            Field.cutoffHertz.rawValue: cutoffHertz,
            Field.resonance.rawValue: resonance,
            Field.midi.rawValue: midi.jsonObject,
        ]
    }

    /// Reads a preset from its canonical JSON, or from any strict JSON object with the same fields.
    public init(json data: Data) throws(PresetRejection) {
        guard data.count <= Self.maximumBytes else { throw .malformed }
        do {
            try StrictJSON.validate(Array(data), maximumDepth: 4, maximumBytes: Self.maximumBytes)
        } catch {
            throw .malformed
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw .malformed }
        try self.init(object: object)
    }

    init(object: [String: Any]) throws(PresetRejection) {
        guard object[Field.format.rawValue] as? String == Self.format else { throw .notAPreset }
        let version = try Self.integer(object, Field.schemaVersion.rawValue)
        guard version <= Self.schemaVersion else { throw .newerVersion(version) }
        guard version == Self.schemaVersion else { throw .outOfRange(Field.schemaVersion.rawValue) }
        if let unknown = object.keys.sorted().first(where: { Field(rawValue: $0) == nil }) { throw .unknownField(unknown) }
        guard let loopName = object[Field.loop.rawValue] as? String else { throw .missingField(Field.loop.rawValue) }
        guard let loop = LoopFixture(rawValue: loopName) else { throw .outOfRange(Field.loop.rawValue) }
        guard let midiObject = object[Field.midi.rawValue] as? [String: Any] else { throw .missingField(Field.midi.rawValue) }
        try self.init(
            loop: loop,
            gainDecibels: Self.number(object, Field.gainDecibels.rawValue),
            filterEnabled: Self.boolean(object, Field.filterEnabled.rawValue),
            cutoffHertz: Self.number(object, Field.cutoffHertz.rawValue),
            resonance: Self.number(object, Field.resonance.rawValue),
            midi: MidiMapping(object: midiObject)
        )
    }

    /// The preset as an item's extras: `{"audioWorkshopPreset": {…}}`.
    public var extras: ItemExtras {
        let data = try! JSONSerialization.data(withJSONObject: [Self.extrasKey: jsonObject], options: [.sortedKeys, .withoutEscapingSlashes])
        // A preset is far below the extras limit and is always a strict JSON object.
        return try! ItemExtras(json: String(decoding: data, as: UTF8.self))
    }

    /// Reads the preset an item's extras hold.
    public init(extras: ItemExtras) throws(PresetRejection) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(extras.json.utf8)) as? [String: Any],
              let preset = object[Self.extrasKey] as? [String: Any] else { throw .notAPreset }
        try self.init(object: preset)
    }

    // JSONSerialization reads a JSON `true` as an NSNumber that also reads as 1, and 1 as one that
    // also reads as `true`, so the type is checked through CoreFoundation's Boolean type.
    static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    static func number(_ object: [String: Any], _ key: String) throws(PresetRejection) -> Double {
        guard let value = object[key] else { throw .missingField(key) }
        guard let number = value as? NSNumber, !isBoolean(number) else { throw .outOfRange(key) }
        return number.doubleValue
    }

    static func integer(_ object: [String: Any], _ key: String) throws(PresetRejection) -> Int {
        let value = try number(object, key)
        guard value.rounded() == value, abs(value) < 1_000_000 else { throw .outOfRange(key) }
        return Int(value)
    }

    static func boolean(_ object: [String: Any], _ key: String) throws(PresetRejection) -> Bool {
        guard let value = object[key] else { throw .missingField(key) }
        guard isBoolean(value), let flag = value as? Bool else { throw .outOfRange(key) }
        return flag
    }
}
