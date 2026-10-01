import Foundation
import LabDomain
import SpeechTimeline

/// Speech Timeline's way into the host (LAB-013). Reads go through `LabDataService` as the app UI;
/// a save goes through `LabLibrary.submit` as a user action, so it runs as the app UI and its
/// receipt joins the session list the inspector reads. It never holds the store.
struct LibrarySpeechBackend: SpeechTimelineBackend {
    let library: LabLibrary

    /// The person's own collections that can take a new item, by title.
    func destinations() async throws(SpeechSaveError) -> [LabCollection] {
        let service: LabDataService
        do { service = try await library.openedService() } catch { throw SpeechSaveError(error) }
        do {
            return try await service.collections(as: LabDataService.appUI)
                .filter { $0.namespace == .user && !$0.isArchived }
                .sorted { $0.title.value.localizedStandardCompare($1.title.value) == .orderedAscending }
        } catch {
            throw .unavailable(LibraryMessages.describe(error))
        }
    }

    /// The person pressed Save for this timeline revision and collection. A new item is not
    /// destructive, so no grant is issued.
    func commit(_ save: TranscriptSave) async throws(SpeechSaveError) -> ActionReceipt {
        guard case .createItem(let draft) = save.operation else { throw .nothingToSave }
        do {
            return try await library.submit(
                save.operation, requestID: save.requestID, authority: .userAction,
                names: [.item(save.itemID): draft.title.value]
            ).receipt
        } catch {
            throw SpeechSaveError(error)
        }
    }
}

extension SpeechSaveError {
    init(_ failure: LabLibrary.SubmitFailure) {
        switch failure {
        case .unavailable(let reason): self = .unavailable(reason)
        case .refused(let error): self = .unavailable(LibraryMessages.describe(error))
        }
    }
}

/// The experiment's own folder: the synthesized sample clip and a copy of imported audio. The
/// experiment's Reset removes it and nothing else; saved transcripts are the person's items.
enum SpeechTimelineFolder {
    static let name = "Speech Timeline"
    static let sampleClip = "sample-clip.caf"

    /// Application Support › Native Lab › Speech Timeline, created if needed.
    static func url() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = support
            .appending(path: LabStoreLocation.folderName, directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

/// The experiment's diagnostics: metadata-only events through the lab's one facade, to the system
/// log. Never the transcript, a file name, or audio.
enum SpeechTimelineDiagnostics {
    static let log = DiagnosticsLog(sinks: [OSLogDiagnosticSink()])
}
