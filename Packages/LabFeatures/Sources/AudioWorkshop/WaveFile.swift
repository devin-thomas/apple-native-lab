import Foundation

/// Audio as planar 32-bit float channels, the form the kernel processes and a WAVE file stores.
public struct PCMAudio: Hashable, Sendable {
    public let sampleRate: Double
    /// One array per channel, all the same length.
    public let channels: [[Float]]

    public init(sampleRate: Double, channels: [[Float]]) {
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public var frameCount: Int { channels.first?.count ?? 0 }
    public var seconds: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }

    /// The largest absolute sample in any channel.
    public var peak: Float { channels.reduce(0) { max($0, $1.reduce(0) { max($0, abs($1)) }) } }

    /// The root-mean-square level over every channel.
    public var rms: Float {
        let count = channels.reduce(0) { $0 + $1.count }
        guard count > 0 else { return 0 }
        var sum: Double = 0
        for channel in channels {
            for sample in channel { sum += Double(sample) * Double(sample) }
        }
        return Float((sum / Double(count)).squareRoot())
    }
}

/// Why a WAVE file was not read. Nothing is processed from a refused file.
public enum WaveFileRejection: Error, Hashable, Sendable {
    case tooLarge(limit: Int)
    case notWave
    case truncated
    case missingFormat
    case missingData
    case unsupportedEncoding(format: UInt16, bits: UInt16)
    case unsupportedChannels(Int)
    case unsupportedSampleRate(Double)
    case tooLong(limitSeconds: Double)
    case empty

    public var message: String {
        switch self {
        case .tooLarge(let limit): "The file is larger than \(limit / 1_048_576) MB. Choose a shorter WAVE file."
        case .notWave: "This is not a WAVE file."
        case .truncated: "The WAVE file ends early or its sizes are wrong."
        case .missingFormat: "The WAVE file has no format description."
        case .missingData: "The WAVE file has no audio data."
        case .unsupportedEncoding(let format, let bits): "The workshop reads 16- and 24-bit PCM and 32-bit float WAVE files, not format \(format) at \(bits) bits."
        case .unsupportedChannels(let count): "The workshop reads mono and stereo files, not \(count) channels."
        case .unsupportedSampleRate(let rate): "The workshop reads 8 to 192 kHz, not \(Int(rate)) Hz."
        case .tooLong(let limit): "The file is longer than \(Int(limit)) seconds."
        case .empty: "The WAVE file holds no samples."
        }
    }
}

/// Reads and writes WAVE files: 16- and 24-bit integer PCM and 32-bit float in, 32-bit float out.
///
/// The reader treats every file as untrusted. It checks each chunk size against the bytes that
/// are really there, reads only what it understands, and refuses anything beyond its limits
/// before it allocates sample memory.
public enum WaveFile {
    public struct Limits: Hashable, Sendable {
        public var maximumBytes = 32 * 1_048_576
        public var maximumSeconds: Double = 120
        public var channels: ClosedRange<Int> = 1...2
        public var sampleRates: ClosedRange<Double> = 8_000...192_000

        public init() {}
    }

    // MARK: Writing

    /// A 32-bit float WAVE file (`WAVE_FORMAT_IEEE_FLOAT`), with the `fact` chunk the format asks
    /// for. The same audio always gives the same bytes.
    public static func encode(_ audio: PCMAudio) -> Data {
        let channelCount = audio.channels.count
        let frames = audio.frameCount
        let dataBytes = frames * channelCount * 4
        var out = Data()
        out.reserveCapacity(58 + dataBytes)
        out.append(contentsOf: Array("RIFF".utf8))
        append32(&out, UInt32(4 + (8 + 18) + (8 + 4) + (8 + dataBytes)))
        out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8))
        append32(&out, 18)
        append16(&out, 3)
        append16(&out, UInt16(channelCount))
        append32(&out, UInt32(audio.sampleRate))
        append32(&out, UInt32(audio.sampleRate) * UInt32(channelCount * 4))
        append16(&out, UInt16(channelCount * 4))
        append16(&out, 32)
        append16(&out, 0)
        out.append(contentsOf: Array("fact".utf8))
        append32(&out, 4)
        append32(&out, UInt32(frames))
        out.append(contentsOf: Array("data".utf8))
        append32(&out, UInt32(dataBytes))
        for frame in 0..<frames {
            for channel in audio.channels { append32(&out, channel[frame].bitPattern) }
        }
        return out
    }

    private static func append16(_ data: inout Data, _ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func append32(_ data: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    // MARK: Reading

    public static func decode(_ data: Data, limits: Limits = Limits()) throws(WaveFileRejection) -> PCMAudio {
        guard data.count <= limits.maximumBytes else { throw .tooLarge(limit: limits.maximumBytes) }
        let bytes = [UInt8](data)
        guard bytes.count >= 12, tag(bytes, 0) == "RIFF", tag(bytes, 8) == "WAVE" else { throw .notWave }

        var format: (tag: UInt16, channels: Int, rate: Double, blockAlign: Int, bits: UInt16)?
        var body: Range<Int>?
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = tag(bytes, offset)
            let size = Int(read32(bytes, offset + 4))
            let start = offset + 8
            guard size <= bytes.count - start else { throw .truncated }
            switch id {
            case "fmt ":
                guard size >= 16 else { throw .truncated }
                var encoding = read16(bytes, start)
                let bits = read16(bytes, start + 14)
                // WAVE_FORMAT_EXTENSIBLE names the real encoding in the first two bytes of its GUID.
                if encoding == 0xFFFE {
                    guard size >= 40 else { throw .truncated }
                    encoding = read16(bytes, start + 24)
                }
                format = (encoding, Int(read16(bytes, start + 2)), Double(read32(bytes, start + 4)), Int(read16(bytes, start + 12)), bits)
            case "data":
                body = start..<(start + size)
            default:
                break
            }
            // Chunks are padded to an even length.
            offset = start + size + (size % 2)
            if format != nil, body != nil { break }
        }

        guard let format else { throw .missingFormat }
        guard let body else { throw .missingData }
        guard limits.channels.contains(format.channels) else { throw .unsupportedChannels(format.channels) }
        guard limits.sampleRates.contains(format.rate) else { throw .unsupportedSampleRate(format.rate) }
        let width: Int
        switch (format.tag, format.bits) {
        case (1, 16): width = 2
        case (1, 24): width = 3
        case (3, 32): width = 4
        default: throw .unsupportedEncoding(format: format.tag, bits: format.bits)
        }
        guard format.blockAlign == width * format.channels else { throw .unsupportedEncoding(format: format.tag, bits: format.bits) }
        let frames = body.count / format.blockAlign
        guard frames > 0 else { throw .empty }
        guard Double(frames) / format.rate <= limits.maximumSeconds else { throw .tooLong(limitSeconds: limits.maximumSeconds) }

        var channels = Array(repeating: [Float](repeating: 0, count: frames), count: format.channels)
        for frame in 0..<frames {
            for channel in 0..<format.channels {
                let at = body.lowerBound + frame * format.blockAlign + channel * width
                channels[channel][frame] = sample(bytes, at, width: width)
            }
        }
        return PCMAudio(sampleRate: format.rate, channels: channels)
    }

    private static func sample(_ bytes: [UInt8], _ at: Int, width: Int) -> Float {
        switch width {
        case 2:
            return Float(Int16(bitPattern: read16(bytes, at))) / 32_768
        case 3:
            let raw = Int32(bytes[at]) | Int32(bytes[at + 1]) << 8 | Int32(bytes[at + 2]) << 16
            return Float((raw << 8) >> 8) / 8_388_608
        default:
            let value = Float(bitPattern: read32(bytes, at))
            // A non-finite sample in a file is data, not a reason to stop; it is read as silence.
            return value.isFinite ? value : 0
        }
    }

    private static func tag(_ bytes: [UInt8], _ at: Int) -> String {
        String(decoding: bytes[at..<(at + 4)], as: UTF8.self)
    }

    private static func read16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func read32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}
