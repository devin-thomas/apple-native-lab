import Foundation

/// Synthesizes a cue's original tone as a quiet 16-bit WAV. The bytes are deterministic. There is
/// no recorded sample and no bundled media file.
public enum CueAudio {
    public static let sampleRate = 16_000

    /// Empty when `amplitude` is 0, which is the muted preference: nothing is handed to a player.
    public static func wav(for tone: CueTone, amplitude: Float) -> Data {
        guard amplitude > 0, tone.pulses > 0, tone.pulseMilliseconds > 0 else { return Data() }
        let samples = render(tone, amplitude: amplitude)
        return wrap(samples)
    }

    static func render(_ tone: CueTone, amplitude: Float) -> [Int16] {
        let pulseSamples = tone.pulseMilliseconds * sampleRate / 1000
        let gapSamples = tone.gapMilliseconds * sampleRate / 1000
        var output: [Int16] = []
        output.reserveCapacity(tone.pulses * (pulseSamples + gapSamples))
        let peak = Int(Float(Int16.max) * min(max(amplitude, 0), 1))
        for pulse in 0..<tone.pulses {
            for index in 0..<pulseSamples {
                let fade = fadeScale(index: index, count: pulseSamples)
                let angle = 2 * Double.pi * tone.frequencyHertz * Double(index) / Double(sampleRate)
                let sample = Int((sin(angle) * Double(peak) * fade).rounded())
                output.append(Int16(clamping: sample))
            }
            if pulse < tone.pulses - 1 {
                output.append(contentsOf: repeatElement(0, count: gapSamples))
            }
        }
        return output
    }

    /// A short fade at each end so a pulse does not click.
    private static func fadeScale(index: Int, count: Int) -> Double {
        let edge = min(40, count / 4)
        guard edge > 0 else { return 1 }
        if index < edge { return Double(index) / Double(edge) }
        let fromEnd = count - 1 - index
        if fromEnd < edge { return Double(fromEnd) / Double(edge) }
        return 1
    }

    private static func wrap(_ samples: [Int16]) -> Data {
        var data = Data()
        let dataBytes = samples.count * 2
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        data.append(uint32(36 + dataBytes))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        data.append(uint32(16))
        data.append(uint16(1)) // PCM
        data.append(uint16(1)) // mono
        data.append(uint32(sampleRate))
        data.append(uint32(sampleRate * 2))
        data.append(uint16(2))
        data.append(uint16(16))
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        data.append(uint32(dataBytes))
        for sample in samples {
            data.append(uint16(UInt16(bitPattern: sample)))
        }
        return data
    }

    private static func uint16(_ value: UInt16) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: 2)
    }

    private static func uint32(_ value: Int) -> Data {
        var little = UInt32(value).littleEndian
        return Data(bytes: &little, count: 4)
    }
}
