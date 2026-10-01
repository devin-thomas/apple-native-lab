import Foundation
import LabDomain
import Testing
@testable import AudioWorkshop

@Suite struct WaveFileTests {
    /// Builds a WAVE file byte by byte, so each hostile case is exact.
    struct Builder {
        var format: UInt16 = 1
        var channels: UInt16 = 1
        var rate: UInt32 = 48_000
        var bits: UInt16 = 16
        var blockAlign: UInt16?
        var formatSize: UInt32 = 16
        var extraChunks: [(String, [UInt8])] = []
        var samples: [UInt8] = []
        var includeFormat = true
        var includeData = true
        var dataSizeOverride: UInt32?

        func bytes() -> Data {
            var body: [UInt8] = Array("WAVE".utf8)
            for (id, content) in extraChunks {
                body += Array(id.utf8) + le32(UInt32(content.count)) + content
                if content.count % 2 == 1 { body.append(0) }
            }
            if includeFormat {
                var fmt = le16(format) + le16(channels) + le32(rate) + le32(rate * UInt32(channels) * UInt32(bits / 8))
                fmt += le16(blockAlign ?? channels * bits / 8) + le16(bits)
                while fmt.count < formatSize { fmt.append(0) }
                body += Array("fmt ".utf8) + le32(formatSize) + fmt
            }
            if includeData {
                body += Array("data".utf8) + le32(dataSizeOverride ?? UInt32(samples.count)) + samples
            }
            return Data(Array("RIFF".utf8) + le32(UInt32(body.count)) + body)
        }

        func le16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
        func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) } }
    }

    @Test func floatFilesRoundTripExactly() throws {
        let audio = PCMAudio(sampleRate: 44_100, channels: [Signal.sine(hertz: 440, seconds: 0.1, sampleRate: 44_100), Signal.sine(hertz: 660, seconds: 0.1, sampleRate: 44_100)])
        let data = WaveFile.encode(audio)
        #expect(data.count == 58 + audio.frameCount * 8)
        #expect(try WaveFile.decode(data) == audio)
        #expect(WaveFile.encode(audio) == data)
    }

    @Test func integerFilesAreReadAtFullScale() throws {
        var sixteen = Builder()
        sixteen.samples = [0x00, 0x80, 0xFF, 0x7F, 0x00, 0x00]
        #expect(try WaveFile.decode(sixteen.bytes()).channels == [[-1, 32_767 / 32_768, 0]])

        var twentyFour = Builder()
        twentyFour.bits = 24
        twentyFour.samples = [0x00, 0x00, 0x80, 0xFF, 0xFF, 0x7F]
        let read = try WaveFile.decode(twentyFour.bytes()).channels[0]
        #expect(read[0] == -1)
        #expect(abs(read[1] - 1) < 1e-6)
    }

    @Test func unknownChunksWithOddLengthsAreSkipped() throws {
        var file = Builder()
        file.extraChunks = [("LIST", [1, 2, 3]), ("junk", [])]
        file.samples = [0x00, 0x40]
        #expect(try WaveFile.decode(file.bytes()).channels == [[0.5]])
    }

    @Test func theExtensibleFormatIsReadByItsSubformat() throws {
        var file = Builder()
        file.format = 0xFFFE
        file.formatSize = 40
        file.bits = 32
        file.samples = withUnsafeBytes(of: Float(0.25).bitPattern.littleEndian, Array.init)
        var bytes = [UInt8](file.bytes())
        // The format chunk's content starts at byte 20; its subformat GUID's first two bytes sit
        // 24 bytes in. 3 is IEEE float.
        bytes[44] = 3
        #expect(try WaveFile.decode(Data(bytes)).channels == [[0.25]])
        bytes[44] = 9
        #expect(throws: WaveFileRejection.unsupportedEncoding(format: 9, bits: 32)) { try WaveFile.decode(Data(bytes)) }
    }

    @Test func hostileFilesAreRefusedBeforeAnythingIsProcessed() {
        func rejection(_ change: (inout Builder) -> Void) -> WaveFileRejection? {
            var file = Builder()
            file.samples = [0, 0, 0, 0]
            change(&file)
            do {
                _ = try WaveFile.decode(file.bytes())
                return nil
            } catch {
                return error
            }
        }
        #expect(throws: WaveFileRejection.notWave) { try WaveFile.decode(Data("RIFX0000WAVE".utf8)) }
        #expect(throws: WaveFileRejection.notWave) { try WaveFile.decode(Data([1, 2, 3])) }
        #expect(rejection { $0.includeFormat = false } == .missingFormat)
        #expect(rejection { $0.includeData = false } == .missingData)
        #expect(rejection { $0.dataSizeOverride = 1_000 } == .truncated)
        #expect(rejection { $0.dataSizeOverride = UInt32.max } == .truncated)
        #expect(rejection { $0.channels = 6; $0.samples = [UInt8](repeating: 0, count: 12) } == .unsupportedChannels(6))
        #expect(rejection { $0.rate = 1_000 } == .unsupportedSampleRate(1_000))
        #expect(rejection { $0.bits = 8 } == .unsupportedEncoding(format: 1, bits: 8))
        #expect(rejection { $0.format = 2 } == .unsupportedEncoding(format: 2, bits: 16))
        #expect(rejection { $0.blockAlign = 7 } == .unsupportedEncoding(format: 1, bits: 16))
        #expect(rejection { $0.samples = [] } == .empty)
        #expect(rejection { $0.formatSize = 12 } == .truncated)
    }

    @Test func limitsAreCheckedBeforeSampleMemoryIsAllocated() {
        var limits = WaveFile.Limits()
        limits.maximumSeconds = 0.01
        var file = Builder()
        file.samples = [UInt8](repeating: 0, count: 48_000 * 2)
        #expect(throws: WaveFileRejection.tooLong(limitSeconds: 0.01)) { try WaveFile.decode(file.bytes(), limits: limits) }
        limits.maximumBytes = 100
        #expect(throws: WaveFileRejection.tooLarge(limit: 100)) { try WaveFile.decode(file.bytes(), limits: limits) }
    }
}

@Suite struct OfflineProcessorTests {
    @Test func anOfflineRenderIsDeterministic() async throws {
        let first = try await OfflineProcessor.renderLoop(.standard, seconds: 2)
        let second = try await OfflineProcessor.renderLoop(.standard, seconds: 2)
        #expect(first.digest == second.digest)
        #expect(first.wave == second.wave)
        #expect(first.audio.frameCount == 96_000)
        #expect(first.stats.frames == 96_000)
        // 96 000 frames in blocks of 512: 187 full blocks and one of 256.
        #expect(first.stats.callbacks == 188)
        #expect(first.audio.peak > 0.05 && first.audio.peak < 1)
        #expect(try WaveFile.decode(first.wave) == first.audio)
    }

    @Test func theRenderMatchesTheKernelRunDirectly() async throws {
        let rendered = try await OfflineProcessor.renderLoop(.standard, seconds: 1)
        let kernel = try preparedKernel { $0.apply(.standard) }
        let direct = KernelRunner(kernel: kernel).renderLoop(frames: 48_000, block: OfflineProcessor.blockFrames)
        #expect(rendered.audio.channels == direct)
    }

    @Test func theSettingsChangeTheSound() async throws {
        let open = try AudioGraphPreset(loop: .noise, gainDecibels: 0, filterEnabled: false, cutoffHertz: 20_000, resonance: 0.7)
        let dark = try AudioGraphPreset(loop: .noise, gainDecibels: 0, filterEnabled: true, cutoffHertz: 200, resonance: 0.7)
        let bright = try await OfflineProcessor.renderLoop(open, seconds: 2)
        let filtered = try await OfflineProcessor.renderLoop(dark, seconds: 2)
        let bypassed = try await OfflineProcessor.renderLoop(dark, bypassed: true, seconds: 2)
        // The noise is high-frequency energy, which shows in the sample-to-sample differences.
        func brightness(_ result: OfflineResult) -> Float {
            let samples = result.audio.channels[0]
            return Signal.rms(zip(samples, samples.dropFirst()).map { $1 - $0 })
        }
        #expect(brightness(filtered) < brightness(bright) / 10)
        #expect(bypassed.digest != filtered.digest)
        // Past the first eighth note's fade-in, the bypassed render is the unfiltered one at 0 dB.
        let open1 = bright.audio.channels[0][12_000...]
        let raw = bypassed.audio.channels[0][12_000...]
        #expect(zip(open1, raw).allSatisfy { abs($0 - $1) < 1e-4 })
    }

    @Test func aWaveFileIsProcessedThroughTheSameGraph() async throws {
        // An original test file: a low and a high tone, mixed, in 16-bit PCM would lose precision,
        // so the file is float.
        let low = Signal.sine(hertz: 150, seconds: 1, amplitude: 0.3)
        let high = Signal.sine(hertz: 9_000, seconds: 1, amplitude: 0.3)
        let mixed = zip(low, high).map { $0 + $1 }
        let file = WaveFile.encode(PCMAudio(sampleRate: 48_000, channels: [mixed]))
        let preset = try AudioGraphPreset(loop: .pulse, gainDecibels: 0, filterEnabled: true, cutoffHertz: 600, resonance: 0.707)
        let result = try await OfflineProcessor.process(waveData: file, named: "two-tones.wav", preset: preset)
        #expect(result.audio.channels.count == 1)
        #expect(result.audio.frameCount == 48_000)
        #expect(result.source == .file(name: "two-tones.wav"))
        #expect(result.suggestedFileName == "two-tones processed.wav")
        // What remains is the low tone.
        let tail = result.audio.channels[0][24_000...]
        #expect(abs(Signal.rms(tail) - Signal.rms(low[24_000...])) < 0.01)
    }

    @Test func anUnreadableFileIsRefusedWithItsReason() async {
        await #expect(throws: OfflineError.unreadable(.notWave)) {
            try await OfflineProcessor.process(waveData: Data("hello".utf8), named: "x.wav", preset: .standard)
        }
    }

    @Test func invalidLengthsAreRefused() async {
        await #expect(throws: OfflineError.invalidLength) { try await OfflineProcessor.renderLoop(.standard, seconds: 0) }
        await #expect(throws: OfflineError.invalidLength) { try await OfflineProcessor.renderLoop(.standard, seconds: 31) }
        await #expect(throws: OfflineError.invalidLength) { try await OfflineProcessor.renderLoop(.standard, seconds: .nan) }
    }

    @Test func aCancelledRenderReturnsNothing() async {
        let task = Task { try await OfflineProcessor.renderLoop(.standard, seconds: 30) }
        task.cancel()
        let result = await task.result
        #expect(throws: OfflineError.cancelled) { try result.get() }
    }
}
