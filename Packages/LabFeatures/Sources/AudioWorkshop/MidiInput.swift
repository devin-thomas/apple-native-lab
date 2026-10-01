#if os(iOS) || os(macOS)
import CoreMIDI
import Foundation
import Synchronization

/// Core MIDI input: one client and one input port, connected to every source the system lists,
/// reconnected when the MIDI setup changes. It opens nothing until `start`, which a person
/// triggers with Listen to MIDI; it never sends MIDI anywhere.
///
/// Messages arrive on Core MIDI's own high-priority thread, not an audio thread. There they are
/// parsed and handed to `receive`, which sets the kernel's cutoff atomically; the log is updated
/// on the main actor.
@MainActor
public final class MidiInput {
    public typealias Receive = @Sendable (_ events: [MidiEvent], _ source: String) -> Void

    public private(set) var sources: [String] = []
    public private(set) var isListening = false
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private let names = SourceNames()
    private let receive: Receive

    public init(receive: @escaping Receive) {
        self.receive = receive
    }

    /// Creates the client and port and connects every source. Returns the names of the sources.
    @discardableResult
    public func start() throws(MidiInputError) -> [String] {
        guard !isListening else { return sources }
        let notify = Self.notifyBlock { [weak self] in self?.connectSources() }
        var status = MIDIClientCreateWithBlock("Native Lab Audio Workshop" as CFString, &client, notify)
        guard status == noErr else { throw .coreMIDI(status) }
        status = MIDIInputPortCreateWithProtocol(client, "Workshop Input" as CFString, ._1_0, &port,
                                                 Self.receiveBlock(names: names, receive: receive))
        guard status == noErr else {
            MIDIClientDispose(client)
            throw .coreMIDI(status)
        }
        isListening = true
        connectSources()
        return sources
    }

    public func stop() {
        guard isListening else { return }
        MIDIPortDispose(port)
        MIDIClientDispose(client)
        port = 0
        client = 0
        isListening = false
        sources = []
        names.set([])
    }

    private func connectSources() {
        guard isListening else { return }
        var found: [String] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
            found.append(name?.takeRetainedValue() as String? ?? "MIDI source \(index + 1)")
            // The connection's reference constant is the source's position in `names`, plus one.
            MIDIPortConnectSource(port, source, UnsafeMutableRawPointer(bitPattern: index + 1))
        }
        names.set(found)
        sources = found
    }

    /// Built outside the main actor, so the block Core MIDI calls on its own thread carries no
    /// actor isolation.
    nonisolated private static func receiveBlock(names: SourceNames, receive: @escaping Receive) -> MIDIReceiveBlock {
        { list, reference in
            let events = Self.events(in: list)
            guard !events.isEmpty else { return }
            let index = Int(bitPattern: reference) - 1
            receive(events, names.name(at: index))
        }
    }

    nonisolated private static func notifyBlock(_ changed: @escaping @MainActor () -> Void) -> MIDINotifyBlock {
        { notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            Task { @MainActor in changed() }
        }
    }

    /// The channel voice messages in an event list, read word by word from its variable-length packets.
    nonisolated static func events(in list: UnsafePointer<MIDIEventList>) -> [MidiEvent] {
        var events: [MidiEvent] = []
        let first = UnsafeRawPointer(list) + MemoryLayout<MIDIEventList>.offset(of: \.packet)!
        var packet = first.assumingMemoryBound(to: MIDIEventPacket.self)
        let wordsOffset = MemoryLayout<MIDIEventPacket>.offset(of: \.words)!
        for _ in 0..<list.pointee.numPackets {
            let count = min(Int(packet.pointee.wordCount), 64)
            let words = UnsafeBufferPointer(start: (UnsafeRawPointer(packet) + wordsOffset).assumingMemoryBound(to: UInt32.self), count: count)
            events += UniversalMidi.events(from: words)
            packet = UnsafePointer(MIDIEventPacketNext(packet))
        }
        return events
    }

    /// Source names shared with Core MIDI's thread.
    private final class SourceNames: Sendable {
        private let storage = Mutex<[String]>([])

        func set(_ names: [String]) { storage.withLock { $0 = names } }

        func name(at index: Int) -> String {
            storage.withLock { $0.indices.contains(index) ? $0[index] : "MIDI source" }
        }
    }
}

public enum MidiInputError: Error, Hashable, Sendable {
    case coreMIDI(OSStatus)

    public var message: String {
        switch self {
        case .coreMIDI(let status): "Core MIDI did not start (\(status)). The on-screen controls still send the same messages."
        }
    }
}
#endif
