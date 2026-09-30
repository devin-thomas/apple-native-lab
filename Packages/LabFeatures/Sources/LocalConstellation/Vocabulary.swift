import Foundation
import PeerSession

/// What a constellation session speaks.
public enum Constellation: SessionVocabulary {
    public static let offer = ProtocolOffer(name: "native-lab.local-constellation", versions: 1...1)

    public static func rolesAllowed(toSend command: ShowCommand) -> Set<PeerRole> {
        // A display only watches. Every command comes from a controller or the conductor itself.
        [.controller, .conductor]
    }

    public static let sampleSenders: Set<PeerRole> = [.controller]
    public static let sampleReceivers: Set<PeerRole> = [.display]

    public typealias Command = ShowCommand
    public typealias Sample = Pointer
    public typealias Snapshot = ShowSnapshot
}

/// What a controller can ask for. Moving between cues changes only the live show; starting or
/// pausing it changes stored state, so a peer can only ask, and the person at the conductor
/// decides.
public enum ShowCommand: WirePayload {
    case next
    case previous
    case goTo(cue: Int)
    case start
    case pause

    public static let wireKeys: Set<String> = ["action", "cue"]

    public var isValid: Bool {
        if case .goTo(let cue) = self { return (0..<CueSheet.maximumCues).contains(cue) }
        return true
    }

    /// Whether the command changes stored state, so a peer's request waits for the conductor's
    /// person and then commits through the operation service.
    public var isSensitive: Bool {
        switch self {
        case .start, .pause: true
        case .next, .previous, .goTo: false
        }
    }

    public var title: String {
        switch self {
        case .next: "Next cue"
        case .previous: "Previous cue"
        case .goTo(let cue): "Go to cue \(cue + 1)"
        case .start: "Start the show"
        case .pause: "Pause the show"
        }
    }

    private enum CodingKeys: String, CodingKey { case action, cue }
    private enum Action: String, Codable { case next, previous, goTo = "go-to", start, pause }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(Action.self, forKey: .action)
        let cue = try container.decodeIfPresent(Int.self, forKey: .cue)
        guard (action == .goTo) == (cue != nil) else {
            throw DecodingError.dataCorruptedError(forKey: .cue, in: container, debugDescription: "Only go-to names a cue.")
        }
        switch action {
        case .next: self = .next
        case .previous: self = .previous
        case .goTo: self = .goTo(cue: cue ?? 0)
        case .start: self = .start
        case .pause: self = .pause
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .next: try container.encode(Action.next, forKey: .action)
        case .previous: try container.encode(Action.previous, forKey: .action)
        case .goTo(let cue):
            try container.encode(Action.goTo, forKey: .action)
            try container.encode(cue, forKey: .cue)
        case .start: try container.encode(Action.start, forKey: .action)
        case .pause: try container.encode(Action.pause, forKey: .action)
        }
    }
}

/// Where the controller points on the display, as fractions of its width and height. A
/// replaceable sample: only the newest matters.
public struct Pointer: WirePayload {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let wireKeys: Set<String> = ["x", "y"]

    public var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

/// The conductor's whole state: which cue, whether the show runs, and the last change.
///
/// It carries the cue's text, so a display needs no copy of the cue sheet, and the text is
/// bounded and cleaned on both sides.
public struct ShowSnapshot: WirePayload {
    public static let maximumTitleLength = 60
    public static let maximumDetailLength = 160
    public static let maximumNoteLength = 160

    public let cue: Int
    public let cueCount: Int
    public let cueTitle: String
    public let cueDetail: String
    public let palette: CuePalette
    public let isRunning: Bool
    /// The stored session's revision, or `nil` when the show was never started.
    public let sessionRevision: Int?
    /// The last change, for people: written by the conductor.
    public let note: String

    public init(
        cue: Int, cueCount: Int, cueTitle: String, cueDetail: String, palette: CuePalette,
        isRunning: Bool, sessionRevision: Int?, note: String
    ) {
        self.cue = cue
        self.cueCount = cueCount
        self.cueTitle = WireText.clean(cueTitle, limit: Self.maximumTitleLength)
        self.cueDetail = WireText.clean(cueDetail, limit: Self.maximumDetailLength)
        self.palette = palette
        self.isRunning = isRunning
        self.sessionRevision = sessionRevision
        self.note = WireText.clean(note, limit: Self.maximumNoteLength)
    }

    public static let wireKeys: Set<String> = ["cue", "cueCount", "cueTitle", "cueDetail", "palette", "isRunning", "sessionRevision", "note"]

    public var isValid: Bool {
        (1...CueSheet.maximumCues).contains(cueCount) && (0..<cueCount).contains(cue) && (sessionRevision ?? 1) >= 1
    }

    private enum CodingKeys: String, CodingKey {
        case cue, cueCount, cueTitle, cueDetail, palette, isRunning, sessionRevision, note
    }

    /// Received text is cleaned and bounded like text written here.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cue: try c.decode(Int.self, forKey: .cue), cueCount: try c.decode(Int.self, forKey: .cueCount),
            cueTitle: try c.decode(String.self, forKey: .cueTitle), cueDetail: try c.decode(String.self, forKey: .cueDetail),
            palette: try c.decode(CuePalette.self, forKey: .palette), isRunning: try c.decode(Bool.self, forKey: .isRunning),
            sessionRevision: try c.decodeIfPresent(Int.self, forKey: .sessionRevision), note: try c.decode(String.self, forKey: .note)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cue, forKey: .cue)
        try c.encode(cueCount, forKey: .cueCount)
        try c.encode(cueTitle, forKey: .cueTitle)
        try c.encode(cueDetail, forKey: .cueDetail)
        try c.encode(palette, forKey: .palette)
        try c.encode(isRunning, forKey: .isRunning)
        try c.encodeIfPresent(sessionRevision, forKey: .sessionRevision)
        try c.encode(note, forKey: .note)
    }

    func with(cue index: Int, from sheet: CueSheet, note: String) -> ShowSnapshot {
        let cue = sheet.cues[index]
        return ShowSnapshot(
            cue: index, cueCount: sheet.cues.count, cueTitle: cue.title, cueDetail: cue.detail, palette: cue.palette,
            isRunning: isRunning, sessionRevision: sessionRevision, note: note
        )
    }

    func with(running: Bool, sessionRevision: Int?, note: String) -> ShowSnapshot {
        ShowSnapshot(
            cue: cue, cueCount: cueCount, cueTitle: cueTitle, cueDetail: cueDetail, palette: palette,
            isRunning: running, sessionRevision: sessionRevision, note: note
        )
    }
}

/// A cue's color scheme, from a fixed set: a peer can name one, never supply a color.
public enum CuePalette: String, Codable, Hashable, Sendable, CaseIterable {
    case dusk, amber, sea, aurora, ember, dawn
}
