import Foundation
import ScreeningRoom
import ScreeningRoomPlayback

/// The one screening this app runs (LAB-031). Every window and page shows the same model, so
/// leaving the page does not stop playback or Picture in Picture, and the resume point is shared.
@MainActor
enum ScreeningRoomHost {
    static let model = ScreeningRoomModel(store: FileResumePointStore(folder: resumeFolder))

    /// The experiment's own folder in Application Support. It holds only the resume point, and
    /// Reset removes only that file.
    static var resumeFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ScreeningRoom", isDirectory: true)
    }
}
