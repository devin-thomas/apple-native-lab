#if os(iOS) || os(macOS)
import AudioToolbox
import AVFAudio
import Foundation

/// The workshop's filter and gain as an AUv3 effect: the same C kernel, its parameters in an
/// `AUParameterTree`, and its preset in `fullState`, so a host saves it with its project and
/// restores it when the project reopens.
///
/// The AUv3 extension serves this class, and the app registers it in-process to host it itself.
/// Its render block is the same shape as the engine's: it pulls input into memory allocated
/// when the unit is created and makes one call into C. It captures only raw pointers.
public final class WorkshopAudioUnit: AUAudioUnit, @unchecked Sendable {
    public static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: fourCharacterCode("wksp"),
        componentManufacturer: fourCharacterCode("NLab"),
        // A sandboxed host, such as the Mac app, finds only components flagged sandbox-safe.
        componentFlags: AudioComponentFlags.sandboxSafe.rawValue,
        componentFlagsMask: 0
    )
    public static let componentName = "Native Lab: Workshop Filter"
    public static let componentVersion: UInt32 = 0x0001_0000
    /// The key the preset's canonical JSON is saved under in `fullState`.
    public static let stateKey = "nativeLab.audioWorkshop.preset"
    /// The parameters a host automates. Bypass is the host's own `shouldBypassEffect`.
    public static let automatable: [WorkshopParameter] = [.gainDecibels, .cutoffHertz, .resonance, .filterEnabled]

    /// Registers the class with the audio component system for this process, once.
    public static func registerInProcess() { _ = registration }

    private static let registration: Void = {
        AUAudioUnit.registerSubclass(WorkshopAudioUnit.self, as: componentDescription, name: componentName, version: componentVersion)
    }()

    private let kernel: AudioKernel
    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private var inputArray: AUAudioUnitBusArray!
    private var outputArray: AUAudioUnitBusArray!
    // Pulled input lands here. Allocated once, freed in deinit, never touched by Swift on the audio thread.
    private let inputMemory: UnsafeMutablePointer<Float>
    private let inputList: UnsafeMutableAudioBufferListPointer
    private let inputChannels: UnsafeMutablePointer<UInt32>
    /// What the preset holds beyond the parameters: the loop and the MIDI mapping.
    private var loop = AudioGraphPreset.standard.loop
    private var midi = AudioGraphPreset.standard.midi

    public override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        kernel = try AudioKernel()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: AudioWorkshop.offlineSampleRate, channels: 2) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputBus.maximumChannelCount = AVAudioChannelCount(AudioKernel.maximumChannels)
        outputBus.maximumChannelCount = AVAudioChannelCount(AudioKernel.maximumChannels)
        inputMemory = .allocate(capacity: AudioKernel.maximumFrames * AudioKernel.maximumChannels)
        inputMemory.initialize(repeating: 0, count: AudioKernel.maximumFrames * AudioKernel.maximumChannels)
        inputList = AudioBufferList.allocate(maximumBuffers: AudioKernel.maximumChannels)
        inputChannels = .allocate(capacity: 1)
        inputChannels.initialize(to: 2)
        try super.init(componentDescription: componentDescription, options: options)

        inputArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = 1_024
        kernel.apply(.standard)
        parameterTree = Self.makeTree(kernel: kernel)
    }

    deinit {
        inputMemory.deallocate()
        free(inputList.unsafeMutablePointer)
        inputChannels.deallocate()
    }

    private static func makeTree(kernel: AudioKernel) -> AUParameterTree {
        let flags: AudioUnitParameterOptions = [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp]
        func parameter(_ id: WorkshopParameter, _ name: String, _ unit: AudioUnitParameterUnit, _ extra: AudioUnitParameterOptions = []) -> AUParameter {
            let created = AUParameterTree.createParameter(
                withIdentifier: id.rawValue, name: name, address: address(of: id),
                min: AUValue(id.range.lowerBound), max: AUValue(id.range.upperBound),
                unit: unit, unitName: nil, flags: flags.union(extra), valueStrings: nil, dependentParameters: nil
            )
            created.value = AUValue(kernel.value(of: id))
            return created
        }
        let tree = AUParameterTree.createTree(withChildren: [
            parameter(.gainDecibels, "Gain", .decibels),
            parameter(.cutoffHertz, "Cutoff", .hertz, .flag_DisplayLogarithmic),
            parameter(.resonance, "Resonance", .generic),
            parameter(.filterEnabled, "Filter", .boolean),
        ])
        // The kernel is the single source of truth: a write from the host or the view goes
        // straight into its atomics, and a read comes back out of them.
        tree.implementorValueObserver = { parameter, value in
            guard let id = WorkshopParameter(address: parameter.address) else { return }
            kernel.set(id, Double(value))
        }
        tree.implementorValueProvider = { parameter in
            guard let id = WorkshopParameter(address: parameter.address) else { return 0 }
            return AUValue(kernel.value(of: id))
        }
        return tree
    }

    static func address(of parameter: WorkshopParameter) -> AUParameterAddress {
        AUParameterAddress(WorkshopParameter.allCases.firstIndex(of: parameter)!)
    }

    public override var inputBusses: AUAudioUnitBusArray { inputArray }
    public override var outputBusses: AUAudioUnitBusArray { outputArray }
    public override var canProcessInPlace: Bool { true }

    public override var shouldBypassEffect: Bool {
        get { kernel.value(of: .bypass) >= 0.5 }
        set { kernel.set(.bypass, newValue ? 1 : 0) }
    }

    public override func allocateRenderResources() throws {
        let channels = Int(outputBus.format.channelCount)
        guard inputBus.format.channelCount == outputBus.format.channelCount,
              inputBus.format.sampleRate == outputBus.format.sampleRate,
              (1...AudioKernel.maximumChannels).contains(channels) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        guard maximumFramesToRender <= AUAudioFrameCount(AudioKernel.maximumFrames) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_TooManyFramesToProcess))
        }
        try super.allocateRenderResources()
        try kernel.prepare(sampleRate: outputBus.format.sampleRate, channels: channels)
        inputChannels.pointee = UInt32(channels)
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        Self.renderBlock(handle: kernel.handle, list: inputList, memory: inputMemory, channels: inputChannels)
    }

    private static func renderBlock(
        handle: KernelHandle,
        list: UnsafeMutableAudioBufferListPointer,
        memory: UnsafeMutablePointer<Float>,
        channels: UnsafeMutablePointer<UInt32>
    ) -> AUInternalRenderBlock {
        let stride = AudioKernel.maximumFrames
        return { _, timestamp, frameCount, _, output, _, pullInput in
            guard frameCount <= UInt32(stride) else { return kAudioUnitErr_TooManyFramesToProcess }
            guard let pullInput else { return kAudioUnitErr_NoConnection }
            let count = Int(channels.pointee)
            list.unsafeMutablePointer.pointee.mNumberBuffers = UInt32(count)
            for channel in 0..<count {
                // The pull may point these at the upstream unit's memory, so they are reset each call.
                list[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frameCount * 4, mData: memory + channel * stride)
            }
            var flags = AudioUnitRenderActionFlags()
            let status = pullInput(&flags, timestamp, frameCount, 0, list.unsafeMutablePointer)
            guard status == noErr else { return status }
            return handle.process(frameCount, from: list.unsafePointer, into: output)
        }
    }

    // MARK: State

    /// The preset the unit holds now: its parameters, loop, and MIDI mapping.
    public var preset: AudioGraphPreset {
        var preset = AudioGraphPreset.standard
        preset.setLoop(loop)
        preset.setMidi(midi)
        for id in Self.automatable { preset.set(id, to: kernel.value(of: id)) }
        return preset
    }

    /// Sets every parameter from a preset, through the tree so hosts and views see the change.
    public func apply(_ preset: AudioGraphPreset) {
        loop = preset.loop
        midi = preset.midi
        let values: [WorkshopParameter: Double] = [
            .gainDecibels: preset.gainDecibels, .cutoffHertz: preset.cutoffHertz,
            .resonance: preset.resonance, .filterEnabled: preset.filterEnabled ? 1 : 0,
        ]
        for (id, value) in values {
            parameterTree?.parameter(withAddress: Self.address(of: id))?.value = AUValue(value)
        }
    }

    /// The base class's state plus the preset's canonical JSON. A state whose preset is missing
    /// or refused leaves the current preset unchanged: a host restoring a damaged project gets
    /// the unit's present sound, not a partial one.
    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            state[Self.stateKey] = preset.canonicalJSON
            return state
        }
        set {
            super.fullState = newValue
            guard let data = newValue?[Self.stateKey] as? Data, let restored = try? AudioGraphPreset(json: data) else { return }
            apply(restored)
        }
    }

    /// Counters from the unit's render callbacks.
    public var stats: RenderStats { kernel.stats }
}

extension WorkshopParameter {
    init?(address: AUParameterAddress) {
        guard address < AUParameterAddress(Self.allCases.count) else { return nil }
        self = Self.allCases[Int(address)]
    }
}

func fourCharacterCode(_ text: StaticString) -> FourCharCode {
    text.withUTF8Buffer { bytes in bytes.reduce(0) { $0 << 8 | FourCharCode($1) } }
}
#endif
