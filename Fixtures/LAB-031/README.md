# LAB-031 Native Screening Room fixtures

Three original clips, drawn by [`make_screening_clips.swift`](make_screening_clips.swift) from numbers and strings in that file, and distributed under the repository's MIT License. No camera, microphone, screen recording, font file, or imported media was used. The pictures are rectangles only (color fields, test bars, a progress bar, and a seven-segment digit), the sound is a generated tone, and the captions were written for this project.

The clips live with the module that bundles them, because every host plays them from its own bundle: [`Packages/LabFeatures/Sources/ScreeningRoomPlayback/Resources/Clips/`](../../Packages/LabFeatures/Sources/ScreeningRoomPlayback/Resources/Clips/). `clips.json` there is the generator's record of each file's size and SHA-256, and `BundledClipTests` checks the bundled bytes against it.

| File | Bytes | SHA-256 | What it is | Expected result |
|---|---|---|---|---|
| `screening-test-card.mov` | 53,517 | `4308e0cb…8af84` | 10 s, 320×180, 15 fps H.264 (software encoder), mono AAC tone stepping each second, and two `tx3g` subtitle tracks in one alternate group: English tagged SDH, and Spanish. Neither is on by default. | Plays everywhere the lab runs; the declared fallback |
| `screening-unknown-codec.mov` | 5,188 | `05d4e4c1…0ca8c9` | 2 s of video only, written as H.264 and relabeled `lab0` in its sample description | `PlaybackFailure.unsupportedCodec(codes: ["lab0"])` |
| `screening-truncated.mov` | 2,048 | `b0e43f37…a44bc5` | The first 2048 bytes of the test card, so the movie header is missing | `PlaybackFailure.unreadable(code: -11829)` (AVFoundation "Cannot Open") |

The captions, English (SDH) then Spanish:

| From | To | English (SDH) | Spanish |
|---|---|---|---|
| 0.5 s | 2.5 s | Test card, part one. | Carta de ajuste, primera parte. |
| 3.0 s | 5.0 s | [a low tone rises] | Sube un tono grave. |
| 5.5 s | 7.5 s | The bar keeps the time. | La barra marca el tiempo. |
| 8.0 s | 9.8 s | End of the test card. | Fin de la carta de ajuste. |

AVFoundation lists four legible options for the test card: each track, plus a forced-only variant of each that it derives. The lab offers only the two tracks, matched by language and the SDH characteristics, never by display name (`CaptionMatcher`).

**Regenerating.** Run `swift Fixtures/LAB-031/make_screening_clips.swift Packages/LabFeatures/Sources/ScreeningRoomPlayback/Resources/Clips` on a Mac. It uses the software H.264 encoder and clears the creation and modification times in the movie, track, and media headers, so two runs on the same macOS and Xcode (macOS 27.0, Xcode 27.0 27A266a, recorded 2026-09-30) wrote identical bytes. Another encoder version may write different bytes that play the same way; commit the new files and `clips.json` together. The script uses AVAssetWriter calls the 27 SDK marks deprecated (`add(_:)`, `startWriting()`, `expectsMediaDataInRealTime`); they still work, and the script is not part of any build.

No protected (DRM) fixture exists, and none will be made: the lab has no way to produce protected content and does not import it. The protected-content path is covered by the error classification (`PlaybackFailure.classify`, AVFoundation code -11831) and by `hasProtectedContent`, which `ClipOpener` checks before anything plays.
