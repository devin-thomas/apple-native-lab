import Foundation
import LabDomain
import Testing
@testable import AudioWorkshop

@Suite struct PresetTests {
    static let sample = try! AudioGraphPreset(
        loop: .chords, gainDecibels: -9.5, filterEnabled: true, cutoffHertz: 1_250, resonance: 1.4,
        midi: MidiMapping(controller: 21, channel: 3, lowHertz: 100, highHertz: 8_000)
    )

    @Test func theCanonicalFormRoundTripsToTheSameBytes() throws {
        let data = Self.sample.canonicalJSON
        let decoded = try AudioGraphPreset(json: data)
        #expect(decoded == Self.sample)
        #expect(decoded.canonicalJSON == data)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix(#"{"cutoffHertz":1250,"filterEnabled":true,"format":"native-lab-audio-preset","#))
        #expect(!text.contains("bypass") && !text.contains("mute"))
    }

    @Test func thePresetRoundTripsThroughItemExtras() throws {
        let extras = Self.sample.extras
        #expect(extras.json.hasPrefix(#"{"audioWorkshopPreset":{"#))
        #expect(try AudioGraphPreset(extras: extras) == Self.sample)
        #expect(throws: PresetRejection.notAPreset) { try AudioGraphPreset(extras: .empty) }
        #expect(throws: PresetRejection.notAPreset) { try AudioGraphPreset(extras: ItemExtras(json: #"{"note":"x"}"#)) }
    }

    /// The exact form docs/DATA_CONTRACTS.md shows.
    @Test func theStandardPresetsExtrasMatchTheDataContract() {
        #expect(AudioGraphPreset.standard.extras.json == #"{"audioWorkshopPreset":{"cutoffHertz":2400,"filterEnabled":true,"format":"native-lab-audio-preset","gainDecibels":-6,"loop":"pulse","midi":{"channel":null,"controller":74,"highHertz":12000,"lowHertz":80},"resonance":0.9,"schemaVersion":1}}"#)
    }

    @Test func aMappingWithAnyChannelStoresNull() throws {
        let text = String(decoding: AudioGraphPreset.standard.canonicalJSON, as: UTF8.self)
        #expect(text.contains(#""channel":null"#))
        #expect(try AudioGraphPreset(json: AudioGraphPreset.standard.canonicalJSON).midi.channel == nil)
    }

    /// Stored presets are data: each of these is refused and nothing is loaded.
    @Test(arguments: [
        (#"not json"#, PresetRejection.malformed),
        (#"[1,2]"#, .malformed),
        (#"{"format":"native-lab-audio-preset","format":"x"}"#, .malformed),
        (#"{"format":"something-else","schemaVersion":1}"#, .notAPreset),
        (#"{"format":"native-lab-audio-preset","schemaVersion":2}"#, .newerVersion(2)),
        (#"{"format":"native-lab-audio-preset","schemaVersion":0}"#, .outOfRange("schemaVersion")),
        (#"{"format":"native-lab-audio-preset","schemaVersion":1.5}"#, .outOfRange("schemaVersion")),
    ])
    func malformedAndForeignPresetsAreRefused(text: String, rejection: PresetRejection) {
        #expect(throws: rejection) { try AudioGraphPreset(json: Data(text.utf8)) }
    }

    @Test func eachFieldIsCheckedByTypeAndRange() throws {
        func refusal(_ change: (inout [String: Any]) -> Void) -> PresetRejection? {
            var object = Self.sample.jsonObject
            change(&object)
            let data = try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
            do {
                _ = try AudioGraphPreset(json: data)
                return nil
            } catch {
                return error
            }
        }
        #expect(refusal { $0["gainDecibels"] = 12 } == .outOfRange("gainDecibels"))
        #expect(refusal { $0["gainDecibels"] = true } == .outOfRange("gainDecibels"))
        #expect(refusal { $0["cutoffHertz"] = 5 } == .outOfRange("cutoffHertz"))
        #expect(refusal { $0["resonance"] = "1" } == .outOfRange("resonance"))
        #expect(refusal { $0["filterEnabled"] = 1 } == .outOfRange("filterEnabled"))
        #expect(refusal { $0["loop"] = "drums" } == .outOfRange("loop"))
        #expect(refusal { $0["volume"] = 1 } == .unknownField("volume"))
        #expect(refusal { $0["bypass"] = true } == .unknownField("bypass"))
        #expect(refusal { $0["midi"] = nil } == .missingField("midi"))
        #expect(refusal { $0["resonance"] = nil } == .missingField("resonance"))
        #expect(refusal { $0["midi"] = ["controller": 120, "channel": NSNull(), "lowHertz": 80, "highHertz": 12_000] } == .outOfRange("midi.controller"))
        #expect(refusal { $0["midi"] = ["controller": 74, "channel": 17, "lowHertz": 80, "highHertz": 12_000] } == .outOfRange("midi.channel"))
        #expect(refusal { $0["midi"] = ["controller": 74, "channel": NSNull(), "lowHertz": 9_000, "highHertz": 900] } == .outOfRange("midi.range"))
        #expect(refusal { $0["midi"] = ["controller": 74, "lowHertz": 80, "highHertz": 12_000] } == .missingField("midi.channel"))
        #expect(refusal { $0["midi"] = ["controller": 74, "channel": NSNull(), "lowHertz": 80, "highHertz": 12_000, "curve": "x"] } == .unknownField("midi.curve"))
    }

    @Test func aPresetIsSmallAndAnOversizedOneIsRefused() {
        #expect(Self.sample.canonicalJSON.count < 400)
        let padded = Data(("{\"format\":\"native-lab-audio-preset\",\"pad\":\"" + String(repeating: "x", count: 5_000) + "\"}").utf8)
        #expect(throws: PresetRejection.malformed) { try AudioGraphPreset(json: padded) }
    }

    @Test func aControlClampsItsValueAndIgnoresNonFiniteInput() {
        var preset = AudioGraphPreset.standard
        preset.set(.gainDecibels, to: 30)
        #expect(preset.gainDecibels == 6)
        preset.set(.cutoffHertz, to: .nan)
        #expect(preset.cutoffHertz == AudioGraphPreset.standard.cutoffHertz)
        preset.set(.loop, to: 1.2)
        #expect(preset.loop == .chords)
        preset.set(.mute, to: 1)
        #expect(preset.gainDecibels == 6)
    }

    @Test func invalidValuesCannotMakeAPreset() {
        #expect(throws: PresetRejection.outOfRange("gainDecibels")) {
            try AudioGraphPreset(loop: .pulse, gainDecibels: .infinity, filterEnabled: true, cutoffHertz: 100, resonance: 1)
        }
        #expect(throws: PresetRejection.outOfRange("resonance")) {
            try AudioGraphPreset(loop: .pulse, gainDecibels: 0, filterEnabled: true, cutoffHertz: 100, resonance: 0.1)
        }
    }
}

@Suite struct MidiTests {
    @Test func controlChangesAndNotesAreReadWithRunningStatus() {
        var parser = MidiByteParser()
        let events = parser.feed([0xB2, 74, 100, 74, 20, 0x92, 60, 90, 60, 0])
        #expect(events == [
            .controlChange(channel: 3, controller: 74, value: 100),
            .controlChange(channel: 3, controller: 74, value: 20),
            .noteOn(channel: 3, note: 60, velocity: 90),
            .noteOff(channel: 3, note: 60, velocity: 0),
        ])
    }

    @Test func realTimeBytesSystemExclusiveAndStrayDataAreSkipped() {
        var parser = MidiByteParser()
        // A stray data byte, a clock byte inside a message, a SysEx, then running status is gone.
        let events = parser.feed([0x10, 0xB0, 0xF8, 7, 64, 0xF0, 0x7E, 0x01, 0xF7, 7, 1, 0xC0, 5, 0xB1, 74])
        #expect(events == [.controlChange(channel: 1, controller: 7, value: 64), .other(channel: 1, status: 0xC0)])
        // The message split across two deliveries completes.
        #expect(parser.feed([33]) == [.controlChange(channel: 2, controller: 74, value: 33)])
    }

    @Test func onScreenEventsAreTheSameBytesAHardwareControllerSends() {
        let sent: [MidiEvent] = [.controlChange(channel: 16, controller: 74, value: 127), .noteOn(channel: 1, note: 69, velocity: 64)]
        var parser = MidiByteParser()
        #expect(parser.feed(sent.flatMap(\.bytes)) == sent)
        #expect(MidiEvent.controlChange(channel: 1, controller: 74, value: 5).bytes == [0xB0, 74, 5])
    }

    @Test func universalPacketsOfBothProtocolsAreRead() {
        let words: [UInt32] = [
            0x20B3_4A40, // MIDI 1.0 CC 74 = 64, channel 4
            0x1000_F800, // a system real-time packet, skipped
            0x40B0_4A00, 0xFFFF_FFFF, // MIDI 2.0 CC 74 at full scale, channel 1
            0x3000_0000, 0x0000_0000, // a two-word data packet, skipped
            0x4090_3C00, 0x0000_0000, // MIDI 2.0 note on with velocity 0 reads as the lowest velocity
        ]
        #expect(UniversalMidi.events(from: words) == [
            .controlChange(channel: 4, controller: 74, value: 64),
            .controlChange(channel: 1, controller: 74, value: 127),
            .noteOn(channel: 1, note: 60, velocity: 1),
        ])
        // A packet cut short is dropped, not read past the end.
        #expect(UniversalMidi.events(from: [0x40B0_4A00]).isEmpty)
    }

    @Test func theMappingIsExponentialBetweenItsEnds() throws {
        let mapping = MidiMapping.standard
        #expect(mapping.cutoff(forValue: 0) == 80)
        #expect(abs(mapping.cutoff(forValue: 127) - 12_000) < 0.001)
        let middle = mapping.cutoff(forValue: 64)
        #expect(abs(middle - 80 * pow(150, 64.0 / 127)) < 0.001)
        #expect((0..<127).allSatisfy { mapping.cutoff(forValue: UInt8($0)) < mapping.cutoff(forValue: UInt8($0 + 1)) })
        #expect((0...127).allSatisfy { mapping.value(forCutoff: mapping.cutoff(forValue: UInt8($0))) == UInt8($0) })
    }

    @Test func onlyTheMappedControllerAndChannelMoveTheCutoff() throws {
        let mapping = try MidiMapping(controller: 21, channel: 2)
        #expect(mapping.cutoff(for: .controlChange(channel: 2, controller: 21, value: 127)) != nil)
        #expect(mapping.cutoff(for: .controlChange(channel: 3, controller: 21, value: 127)) == nil)
        #expect(mapping.cutoff(for: .controlChange(channel: 2, controller: 74, value: 127)) == nil)
        #expect(mapping.cutoff(for: .noteOn(channel: 2, note: 21, velocity: 127)) == nil)
        #expect(MidiMapping.standard.cutoff(for: .controlChange(channel: 9, controller: 74, value: 0)) == 80)
    }

    @Test func aMappedEventSetsTheKernelsCutoff() throws {
        let kernel = try AudioKernel()
        var parser = MidiByteParser()
        for event in parser.feed([0xB0, 74, 127]) {
            if let cutoff = MidiMapping.standard.cutoff(for: event) { kernel.set(.cutoffHertz, cutoff) }
        }
        #expect(abs(kernel.value(of: .cutoffHertz) - 12_000) < 0.01)
    }

    @Test func channelModeControllersCannotBeMapped() {
        #expect(throws: PresetRejection.outOfRange("midi.controller")) { try MidiMapping(controller: 123) }
        #expect(MidiMapping.standard.with(controller: 127).controller == 119)
    }
}
