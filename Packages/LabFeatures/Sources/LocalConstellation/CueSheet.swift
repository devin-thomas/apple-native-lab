import Foundation
import LabDomain
import PeerSession

/// The show's original fixture: a short list of cues, bundled with the module.
public struct CueSheet: Hashable, Sendable {
    public static let maximumCues = 32
    public static let maximumBytes = 16 * 1024

    public struct Cue: Hashable, Sendable, Codable {
        public let id: String
        public let title: String
        public let detail: String
        public let palette: CuePalette
    }

    public let title: String
    public let cues: [Cue]

    /// The bundled cue sheet.
    public static func bundled() throws(CueSheetError) -> CueSheet {
        guard let url = Bundle.module.url(forResource: "cue-sheet", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw .missing
        }
        return try CueSheet(data: data)
    }

    /// Reads and validates a cue sheet: strict JSON, known fields only, 1 to 32 cues with unique
    /// IDs and bounded text.
    public init(data: Data) throws(CueSheetError) {
        do {
            try StrictJSON.validate(data, maximumDepth: 4, maximumBytes: Self.maximumBytes)
        } catch {
            throw .invalid
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["format", "formatVersion", "title", "cues"],
              object["format"] as? String == "native-lab-cue-sheet",
              let cueObjects = object["cues"] as? [[String: Any]],
              cueObjects.allSatisfy({ Set($0.keys) == ["id", "title", "detail", "palette"] }) else {
            throw .invalid
        }
        guard object["formatVersion"] as? Int == 1 else { throw .unsupportedVersion }
        struct File: Decodable {
            let title: String
            let cues: [Cue]
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { throw .invalid }
        guard (1...Self.maximumCues).contains(file.cues.count),
              Set(file.cues.map(\.id)).count == file.cues.count,
              file.cues.allSatisfy({ cue in
                  !cue.id.isEmpty && cue.id.count <= 40
                      && WireText.clean(cue.title, limit: ShowSnapshot.maximumTitleLength) == cue.title && !cue.title.isEmpty
                      && WireText.clean(cue.detail, limit: ShowSnapshot.maximumDetailLength) == cue.detail
              }) else {
            throw .invalid
        }
        title = WireText.clean(file.title, limit: 80)
        cues = file.cues
    }

    /// The state a new show starts in: the first cue, paused unless the stored session runs.
    public func openingSnapshot(session: LabSession?) -> ShowSnapshot {
        let first = cues[0]
        return ShowSnapshot(
            cue: 0, cueCount: cues.count, cueTitle: first.title, cueDetail: first.detail, palette: first.palette,
            isRunning: session?.isRunning ?? false, sessionRevision: session?.revision.rawValue,
            note: "Ready at the first cue."
        )
    }
}

public enum CueSheetError: Error, Hashable, Sendable {
    case missing
    case invalid
    case unsupportedVersion
}
