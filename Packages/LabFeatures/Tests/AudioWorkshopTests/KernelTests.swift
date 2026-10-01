import CoreAudioTypes
import Foundation
import Testing
@testable import AudioWorkshop

/// The C kernel through its Swift handle, with synthesized signals only: the ramps, bypass, panic
/// mute, filter, limit, counters, and every refusal.
@Suite struct KernelTests {
    // MARK: Formats and parameters

    @Test(arguments: [(0.0, 2), (-48_000.0, 2), (Double.nan, 2), (1_000_000.0, 2), (48_000.0, 0), (48_000.0, 3)])
    func anUnsupportedFormatIsRefused(rate: Double, channels: Int) throws {
        let kernel = try AudioKernel()
        let error = #expect(throws: AudioKernelError.self) { try kernel.prepare(sampleRate: rate, channels: channels) }
        guard case .unsupportedFormat(_, let refused) = error else {
            Issue.record("expected an unsupported format")
            return
        }
        #expect(refused == channels)
    }

    @Test func parametersAreClampedAndNonFiniteValuesChangeNothing() throws {
        let kernel = try AudioKernel()
        kernel.set(.gainDecibels, 40)
        #expect(kernel.value(of: .gainDecibels) == 6)
        kernel.set(.gainDecibels, -500)
        #expect(kernel.value(of: .gainDecibels) == -60)
        kernel.set(.cutoffHertz, 5)
        #expect(kernel.value(of: .cutoffHertz) == 20)
        kernel.set(.resonance, 100)
        #expect(kernel.value(of: .resonance) == 8)
        kernel.set(.loop, 7.6)
        #expect(kernel.value(of: .loop) == 2)
        kernel.set(.mute, 0.7)
        #expect(kernel.value(of: .mute) == 1)
        kernel.set(.cutoffHertz, 1_000)
        kernel.set(.cutoffHertz, .nan)
        kernel.set(.cutoffHertz, .infinity)
        #expect(kernel.value(of: .cutoffHertz) == 1_000)
    }

    @Test func beforePrepareARenderIsSilentAndSaysUninitialized() throws {
        let kernel = try AudioKernel()
        let (output, statuses) = KernelRunner(kernel: kernel).process([Signal.constant(0.5, frames: 64)])
        #expect(statuses == [-10867])
        #expect(output[0].allSatisfy { $0 == 0 })
    }

    // MARK: Determinism

    @Test(arguments: LoopFixture.allCases)
    func theOriginalLoopIsDeterministicAndRepeatsEveryTwoSeconds(loop: LoopFixture) throws {
        let configure: (AudioKernel) -> Void = { $0.set(.loop, loop.kernelValue); $0.set(.bypass, 1) }
        let first = KernelRunner(kernel: try preparedKernel(sampleRate: 44_100, configure: configure)).renderLoop(frames: 44_100 * 4)
        let second = KernelRunner(kernel: try preparedKernel(sampleRate: 44_100, configure: configure)).renderLoop(frames: 44_100 * 4)
        #expect(first == second)
        // Bypassed, the output is the loop itself: the second two seconds repeat the first.
        let loopFrames = 44_100 * 2
        #expect(zip(first[0][0..<loopFrames], first[0][loopFrames...]).allSatisfy { abs($0 - $1) < 1e-6 })
        #expect(first[0] == first[1])
        #expect(Signal.rms(first[0]) > 0.01)
        #expect(first[0].allSatisfy { abs($0) < 0.6 })
    }

    @Test func theThreeLoopsDiffer() throws {
        let renders = try LoopFixture.allCases.map { loop in
            KernelRunner(kernel: try preparedKernel { $0.set(.loop, loop.kernelValue) }).renderLoop(frames: 4_800)[0]
        }
        #expect(Set(renders.map { $0.map(\.bitPattern) }).count == 3)
    }

    // MARK: No gain jumps

    @Test func everyPrepareFadesInFromSilence() throws {
        let kernel = try preparedKernel { $0.set(.filterEnabled, 0); $0.set(.gainDecibels, 0) }
        let (output, _) = KernelRunner(kernel: kernel).process([Signal.constant(0.5, frames: 48_000)])
        #expect(abs(output[0][0]) < 0.001)
        #expect(Signal.maximumStep(output[0]) < 0.001)
        // Twenty time constants later the level is at unity gain.
        #expect(abs(output[0][47_999] - 0.5) < 0.0005)
        #expect(abs(kernel.stats.currentLevel - 1) < 0.001)
    }

    @Test func aLargeGainChangeRampsInsteadOfJumping() throws {
        let kernel = try preparedKernel { $0.set(.filterEnabled, 0); $0.set(.gainDecibels, -40) }
        let runner = KernelRunner(kernel: kernel)
        _ = runner.process([Signal.constant(0.25, frames: 24_000)])
        kernel.set(.gainDecibels, 6)
        let (output, _) = runner.process([Signal.constant(0.25, frames: 24_000)])
        // From -40 dB to +6 dB is a factor of 200. A jump would move one sample by about 0.5.
        #expect(Signal.maximumStep(output[0]) < 0.001)
        #expect(output[0].last! > 0.49)
    }

    // MARK: Bypass and panic mute

    @Test func panicMuteSilencesWithinMillisecondsAndHoldsSilence() throws {
        let kernel = try preparedKernel { $0.set(.gainDecibels, 0); $0.set(.filterEnabled, 0) }
        let runner = KernelRunner(kernel: kernel)
        _ = runner.process([Signal.sine(hertz: 440, seconds: 0.5)])
        kernel.set(.mute, 1)
        let (output, _) = runner.process([Signal.sine(hertz: 440, seconds: 0.5)])
        // A 3 ms time constant: after 60 ms (2 880 frames) every sample is exactly zero.
        #expect(output[0][2_880...].allSatisfy { $0 == 0 })
        #expect(Signal.maximumStep(output[0]) < 0.05)
        #expect(kernel.stats.currentLevel == 0)
    }

    @Test func panicMuteSilencesTheBypassedSignalToo() throws {
        let kernel = try preparedKernel { $0.set(.bypass, 1); $0.set(.mute, 1) }
        let (output, _) = KernelRunner(kernel: kernel).process([Signal.sine(hertz: 440, seconds: 0.2)])
        #expect(output[0].allSatisfy { $0 == 0 })
    }

    @Test func unmutingFadesBackIn() throws {
        let kernel = try preparedKernel { $0.set(.gainDecibels, 0); $0.set(.filterEnabled, 0); $0.set(.mute, 1) }
        let runner = KernelRunner(kernel: kernel)
        _ = runner.process([Signal.constant(0.5, frames: 4_800)])
        kernel.set(.mute, 0)
        let (output, _) = runner.process([Signal.constant(0.5, frames: 24_000)])
        #expect(Signal.maximumStep(output[0]) < 0.001)
    }

    @Test func bypassPassesTheInputThroughWhateverTheGainAndFilter() throws {
        let kernel = try preparedKernel {
            $0.set(.bypass, 1)
            $0.set(.gainDecibels, -60)
            $0.set(.cutoffHertz, 100)
        }
        let input = Signal.sine(hertz: 5_000, seconds: 0.2)
        let (output, _) = KernelRunner(kernel: kernel).process([input])
        #expect(zip(input, output[0]).allSatisfy { abs($0 - $1) < 1e-5 })
    }

    @Test func switchingBypassCrossfades() throws {
        let kernel = try preparedKernel { $0.set(.gainDecibels, -20); $0.set(.filterEnabled, 0) }
        let runner = KernelRunner(kernel: kernel)
        _ = runner.process([Signal.constant(0.5, frames: 24_000)])
        kernel.set(.bypass, 1)
        let (output, _) = runner.process([Signal.constant(0.5, frames: 24_000)])
        #expect(Signal.maximumStep(output[0]) < 0.005)
        #expect(abs(output[0].last! - 0.5) < 1e-4)
    }

    // MARK: The filter

    @Test func theLowPassKeepsLowTonesAndCutsHighOnes() throws {
        func level(_ hertz: Double) throws -> Float {
            let kernel = try preparedKernel { $0.set(.gainDecibels, 0); $0.set(.cutoffHertz, 500); $0.set(.resonance, 0.707) }
            let (output, _) = KernelRunner(kernel: kernel).process([Signal.sine(hertz: hertz, seconds: 0.5)])
            return Signal.rms(output[0][12_000...])
        }
        let low = try level(100)
        let high = try level(8_000)
        #expect(low > 0.33)
        // Two octaves above twelve dB per octave: 8 kHz is four octaves above 500 Hz.
        #expect(high < low / 100)
    }

    @Test func turningTheFilterOffPassesHighTones() throws {
        let kernel = try preparedKernel { $0.set(.gainDecibels, 0); $0.set(.cutoffHertz, 500); $0.set(.filterEnabled, 0) }
        let (output, _) = KernelRunner(kernel: kernel).process([Signal.sine(hertz: 8_000, seconds: 0.5)])
        #expect(Signal.rms(output[0][12_000...]) > 0.34)
    }

    @Test func aCutoffAboveTheNyquistLimitStaysStable() throws {
        let kernel = try preparedKernel(sampleRate: 8_000) { $0.set(.gainDecibels, 0); $0.set(.cutoffHertz, 20_000); $0.set(.resonance, 8) }
        let (output, _) = KernelRunner(kernel: kernel).process([Signal.sine(hertz: 1_000, seconds: 1, sampleRate: 8_000)])
        #expect(output[0].allSatisfy { $0.isFinite })
        #expect(kernel.stats.nonFiniteSamples == 0)
    }

    // MARK: Refusals, limits, and counters

    @Test func anOversizedCallRendersSilenceAndIsCounted() throws {
        let kernel = try preparedKernel()
        let (output, statuses) = KernelRunner(kernel: kernel).process([Signal.constant(0.5, frames: 5_000)], block: 5_000)
        #expect(statuses == [-10874])
        #expect(output[0][..<AudioKernel.maximumFrames].allSatisfy { $0 == 0 })
        #expect(kernel.stats.oversizedCalls == 1)
    }

    @Test func nonFiniteInputBecomesSilenceAndTheFilterRecovers() throws {
        let kernel = try preparedKernel { $0.set(.gainDecibels, 0) }
        var input = Signal.sine(hertz: 200, seconds: 0.1)
        input[100] = .nan
        input[200] = .infinity
        let runner = KernelRunner(kernel: kernel)
        let (output, _) = runner.process([input])
        #expect(output[0].allSatisfy { $0.isFinite })
        #expect(kernel.stats.nonFiniteSamples >= 2)
        let (after, _) = runner.process([Signal.sine(hertz: 200, seconds: 0.2)])
        #expect(after[0].allSatisfy { $0.isFinite })
        #expect(Signal.rms(after[0][4_800...]) > 0.3)
    }

    @Test func theSafetyLimitHoldsFullScaleAndCountsIt() throws {
        let kernel = try preparedKernel { $0.set(.gainDecibels, 6); $0.set(.filterEnabled, 0) }
        let (output, _) = KernelRunner(kernel: kernel).process([Signal.constant(4, frames: 24_000)])
        #expect(output[0].allSatisfy { abs($0) <= 1 })
        #expect(kernel.stats.clippedSamples > 0)
        #expect(kernel.stats.maximumPeak == 1)
    }

    @Test func monoInputFeedsBothOutputChannels() throws {
        let kernel = try preparedKernel { $0.set(.bypass, 1) }
        let input = Signal.sine(hertz: 300, seconds: 0.05)
        let inList = AudioBufferList.allocate(maximumBuffers: 1)
        let outList = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(inList.unsafeMutablePointer); free(outList.unsafeMutablePointer) }
        var source = input
        var left = [Float](repeating: 9, count: input.count)
        var right = [Float](repeating: 9, count: input.count)
        let bytes = UInt32(input.count * 4)
        source.withUnsafeMutableBufferPointer { src in
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    inList[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: src.baseAddress)
                    outList[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: l.baseAddress)
                    outList[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: r.baseAddress)
                    _ = kernel.handle.process(UInt32(input.count), from: inList.unsafePointer, into: outList.unsafeMutablePointer)
                }
            }
        }
        #expect(left == right)
        #expect(zip(left, input).allSatisfy { abs($0 - $1) < 1e-5 })
    }

    @Test func outputBuffersWithoutMemoryUseTheKernelsOwn() throws {
        let kernel = try preparedKernel()
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(list.unsafeMutablePointer) }
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
        #expect(kernel.handle.renderLoop(256, into: list.unsafeMutablePointer) == 0)
        #expect(list[0].mData != nil && list[1].mData != nil)
        #expect(list[0].mDataByteSize == 1_024)
    }

    @Test func channelsBeyondThePreparedCountAreSilent() throws {
        let kernel = try preparedKernel(channels: 1) { $0.set(.bypass, 1) }
        let (output, _) = KernelRunner(kernel: kernel).process([Signal.constant(0.5, frames: 512), Signal.constant(0.5, frames: 512)])
        #expect(output[0].allSatisfy { abs($0 - 0.5) < 1e-5 })
        #expect(output[1].allSatisfy { $0 == 0 })
    }

    @Test func statsCountCallsAndFramesAndPrepareStartsANewGeneration() throws {
        let kernel = try preparedKernel()
        let runner = KernelRunner(kernel: kernel)
        _ = runner.renderLoop(frames: 1_000, block: 250)
        var stats = kernel.stats
        #expect(stats.callbacks == 4)
        #expect(stats.frames == 1_000)
        #expect(stats.sampleRate == 48_000 && stats.channels == 2)
        let generation = stats.generation
        try kernel.prepare(sampleRate: 44_100, channels: 1)
        stats = kernel.stats
        #expect(stats.generation == generation + 1)
        #expect(stats.callbacks == 0 && stats.frames == 0)
        #expect(stats.sampleRate == 44_100 && stats.channels == 1)
    }

    @Test func aPresetSetsEveryParameterButNeverBypassOrMute() throws {
        let kernel = try AudioKernel()
        kernel.set(.mute, 1)
        kernel.set(.bypass, 1)
        let preset = try AudioGraphPreset(loop: .noise, gainDecibels: -12, filterEnabled: false, cutoffHertz: 900, resonance: 2)
        kernel.apply(preset)
        #expect(kernel.value(of: .loop) == 2)
        #expect(kernel.value(of: .gainDecibels) == -12)
        #expect(kernel.value(of: .filterEnabled) == 0)
        #expect(kernel.value(of: .cutoffHertz) == 900)
        #expect(kernel.value(of: .resonance) == 2)
        #expect(kernel.value(of: .mute) == 1)
        #expect(kernel.value(of: .bypass) == 1)
    }
}
