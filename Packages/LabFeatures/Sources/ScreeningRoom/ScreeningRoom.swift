import Foundation

/// LAB-031 Native Screening Room: watch an original clip, move it between playback surfaces, and
/// come back to the same position and captions.
///
/// This target is the platform-free half: the clips, the playback state, the commands and the
/// system signals that change it, the receipts, and the resume point. It imports Foundation and
/// LabDomain only, so it compiles on every host and its rules are tested without a player. The
/// AVFoundation, AVKit, and MediaPlayer adapters live in `ScreeningRoomPlayback`.
public enum ScreeningRoom {
    public static let experimentID = "LAB-031"
    public static let title = "Native Screening Room"
    public static let symbol = "play.rectangle.on.rectangle"

    /// How far the skip commands and the remote's skip buttons move, in seconds.
    public static let skipInterval: Double = 10
}

/// The clips this build carries. All three are original and drawn by
/// `Fixtures/LAB-031/make_screening_clips.swift`; none came from a camera, a person, or a service.
public enum ScreeningClips {
    /// The clip the experiment opens: ten seconds of a drawn test card with a stepping tone and two
    /// subtitle tracks, English captions (SDH) and Spanish subtitles, neither on by default.
    public static let testCard = MediaAsset(
        id: MediaAssetID("screening-test-card"),
        title: "Test Card",
        resourceName: "screening-test-card",
        fileExtension: "mov",
        duration: 10,
        captions: [
            SubtitleTrack(id: "en-sdh", languageTag: "en", title: "English (SDH)", isForDeafAndHardOfHearing: true),
            SubtitleTrack(id: "es", languageTag: "es", title: "Spanish", isForDeafAndHardOfHearing: false),
        ],
        expectation: .plays
    )

    /// Two seconds of video whose sample entry names a codec no decoder claims (`lab0`).
    public static let unknownCodec = MediaAsset(
        id: MediaAssetID("screening-unknown-codec"),
        title: "Unknown Codec",
        resourceName: "screening-unknown-codec",
        fileExtension: "mov",
        duration: 2,
        captions: [],
        expectation: .fails(.unsupportedCodec(codes: ["lab0"]))
    )

    /// The first 2048 bytes of the test card: the movie header is missing, so nothing can open it.
    public static let truncated = MediaAsset(
        id: MediaAssetID("screening-truncated"),
        title: "Truncated File",
        resourceName: "screening-truncated",
        fileExtension: "mov",
        duration: nil,
        captions: [],
        expectation: .fails(.unreadable(code: -11829))
    )

    /// In the order the experiment lists them: the clip to watch, then the two that must fail.
    public static let all = [testCard, unknownCodec, truncated]

    public static func clip(_ id: MediaAssetID) -> MediaAsset? {
        all.first { $0.id == id }
    }
}
