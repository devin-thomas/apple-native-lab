import CoreAudioTypes
import Foundation
import LabDomain
import Synchronization
@testable import AudioWorkshop

/// Original test signals, synthesized here: sines, constants, and nothing recorded.
enum Signal {
    static func sine(hertz: Double, seconds: Double, sampleRate: Double = 48_000, amplitude: Float = 0.5) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { amplitude * Float(sin(2 * Double.pi * hertz * Double($0) / sampleRate)) }
    }

    static func constant(_ value: Float, frames: Int) -> [Float] {
        [Float](repeating: value, count: frames)
    }

    static func rms(_ samples: some Collection<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return Float((sum / Double(samples.count)).squareRoot())
    }

    static func maximumStep(_ samples: [Float]) -> Float {
        zip(samples, samples.dropFirst()).reduce(0) { max($0, abs($1.1 - $1.0)) }
    }
}

/// Runs a kernel over planar channels in blocks, the way a render callback would, and returns the
/// output and every call's status.
struct KernelRunner {
    let kernel: AudioKernel

    func process(_ input: [[Float]], block: Int = 256) -> (output: [[Float]], statuses: [OSStatus]) {
        let channels = input.count
        let frames = input.first?.count ?? 0
        var output = Array(repeating: [Float](repeating: 0, count: frames), count: channels)
        var statuses: [OSStatus] = []
        let inList = AudioBufferList.allocate(maximumBuffers: channels)
        let outList = AudioBufferList.allocate(maximumBuffers: channels)
        let inMemory = UnsafeMutablePointer<Float>.allocate(capacity: block * channels)
        let outMemory = UnsafeMutablePointer<Float>.allocate(capacity: block * channels)
        defer {
            free(inList.unsafeMutablePointer)
            free(outList.unsafeMutablePointer)
            inMemory.deallocate()
            outMemory.deallocate()
        }
        var done = 0
        while done < frames {
            let count = min(block, frames - done)
            for channel in 0..<channels {
                for frame in 0..<count { inMemory[channel * block + frame] = input[channel][done + frame] }
                inList[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * 4), mData: inMemory + channel * block)
                outList[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * 4), mData: outMemory + channel * block)
            }
            statuses.append(kernel.handle.process(UInt32(count), from: inList.unsafePointer, into: outList.unsafeMutablePointer))
            for channel in 0..<channels {
                for frame in 0..<count { output[channel][done + frame] = outMemory[channel * block + frame] }
            }
            done += count
        }
        return (output, statuses)
    }

    func renderLoop(frames: Int, channels: Int = 2, block: Int = 256) -> [[Float]] {
        var output = Array(repeating: [Float](), count: channels)
        let list = AudioBufferList.allocate(maximumBuffers: channels)
        let memory = UnsafeMutablePointer<Float>.allocate(capacity: block * channels)
        defer {
            free(list.unsafeMutablePointer)
            memory.deallocate()
        }
        var done = 0
        while done < frames {
            let count = min(block, frames - done)
            for channel in 0..<channels {
                list[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * 4), mData: memory + channel * block)
            }
            _ = kernel.handle.renderLoop(UInt32(count), into: list.unsafeMutablePointer)
            for channel in 0..<channels {
                output[channel].append(contentsOf: UnsafeBufferPointer(start: memory + channel * block, count: count))
            }
            done += count
        }
        return output
    }
}

func preparedKernel(sampleRate: Double = 48_000, channels: Int = 2, configure: (AudioKernel) -> Void = { _ in }) throws -> AudioKernel {
    let kernel = try AudioKernel()
    configure(kernel)
    try kernel.prepare(sampleRate: sampleRate, channels: channels)
    return kernel
}

/// The host's rules over an in-memory store: `GrantAuthorizationPolicy` and one actor, the way the
/// hosts' `LabDataService` composes the real store.
final class ServicePresetBackend: PresetBackend {
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))

    let store = InMemoryOperationStore()
    let ledger = GrantLedger()
    let service: OperationService
    let actor: ActorScope
    private let log = Mutex<[ActionReceipt]>([])

    init(actor: ActorScope = ServicePresetBackend.appUI) {
        self.actor = actor
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
    }

    func collection(_ id: CollectionID) async throws(PresetStoreError) -> LabCollection? {
        do {
            return try await service.findCollection(id, as: actor)
        } catch .notFound {
            return nil
        } catch {
            throw .refused(error)
        }
    }

    func items(in collection: CollectionID) async throws(PresetStoreError) -> [LabItem] {
        let filter = try! ItemFilter(collectionID: collection, includeArchived: true, limit: 200)
        do {
            return try await service.findItems(filter, as: actor)
        } catch {
            throw .refused(error)
        }
    }

    func commit(_ operation: DomainOperation, requestID: RequestID, names: [EntityReference: String]) async throws(PresetStoreError) -> ActionReceipt {
        let receipt: ActionReceipt
        do {
            receipt = try await service.perform(OperationRequest(id: requestID, operation: operation, actor: actor))
        } catch {
            throw .refused(error)
        }
        log.withLock { $0.append(receipt) }
        return receipt
    }

    var receipts: [ActionReceipt] { log.withLock { $0 } }
}
