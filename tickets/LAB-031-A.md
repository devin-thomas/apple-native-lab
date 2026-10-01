---
id: "LAB-031-A"
title: "Implement Native Screening Room"
status: "done"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "CORE-013", "LAB-008-B"]
---

# LAB-031-A — Implement Native Screening Room

## Goal

Watch a rights-cleared clip, switch native playback surfaces, and resume without losing position or captions.

## Authority and scope

Read the [governing specification](../experiments/LAB-031-native-screening-room.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** native-screening-room module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Import or use original sample media
3. Use native playback controls and remote commands
4. Add caption/track selection
5. Probe PiP and AirPlay per platform
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Audio interruptions and route changes preserve correct state. (Fixture path: the signals are delivered as the adapters deliver them; no real call, alarm, or unplugged output was produced. An interruption pauses and resumes only when the clip was playing and the system recommends it; the player's own interrupted-rate report keeps that plan whatever order the two reports arrive in; a person's pause during it is kept; a lost output pauses and stays paused, also across an interruption; a new output keeps playing; position and captions never move (`InterruptionAndRouteTests`, 11). With a real `AVPlayer` over the test card, the interruption paused the player and its end resumed it with Spanish captions still selected, and a lost output paused it (`anInterruptionPausesThePlayerAndItsEndResumesIt`, `aLostOutputPausesAndStaysPaused`). The notification raw values match the SDK's enums in the tvOS 27.0 simulator (`audioSessionNotificationsBecomeSignals`).)
- [x] Caption selection survives a presentation change. (In the session for every surface, including the system's full screen, Picture in Picture, and AirPlay (`captionsAndPositionSurviveEveryPresentationChange`); in the player itself, on one item that is never reloaded, on the Mac, in the iOS 27.0 simulator's hosted run, and in the tvOS 27.0 simulator (`captionSelectionSurvivesEveryPresentationChangeInThePlayerItself`, `ScreeningRoomHostTests`, `ScreeningRoomPhoneTests`, `ScreeningRoomTVTests`); and with the remote alone in the tvOS simulator: Spanish chosen on the page, Watch in Theater opened the system player full screen, Menu returned to the page, and the page still read "Spanish · In the page" with receipts for both moves (`ScreeningRoomRemoteUITests`). That UI test first failed: the system player re-applied the system caption preference and turned Spanish off. Automatic media selection is now off; see the spec's notes.)
- [x] Unavailable codec or protected content shows a real error. (Unavailable codec and a damaged file: AVFoundation itself, on the Mac and in the iOS and tvOS simulators, reads the unknown-codec clip as not playable with track code `lab0` and the truncated clip as error -11829, and the page shows "Format not supported" or "Clip can't be opened" with what still works; nothing is handed to the player (`ClipOpenerTests`, `anUnplayableClipShowsItsErrorAndTheTestCardStillPlays`). Protected content: handled (`hasProtectedContent`, error -11831) and its message tested, but never observed, because no protected fixture exists or will be made.)
- [x] Fallback is usable: In-app local playback using a small universally supported fixture.. (The 53,517-byte H.264/AAC test card is the fallback and the default clip. It opened and played inside the built Mac app (hosted), the iPhone app in the iOS 27.0 simulator (hosted), and the Apple TV app in the tvOS 27.0 simulator, where the remote-driven test saw its picture in the page and in the theater. The Mac and iPhone pages were built but not walked through by hand.)
- [x] Sensitive operations share the domain authorization/receipt path. (Playback is live session state, so its commands do not go to `OperationService`'s store, but they are authorized by the same domain rules and answered the same way: LabDomain's `ActorScope`, fixed `AdapterKind` ceilings, and grants decide each command, every request ID gets one receipt with previous and new revisions and an undo where one exists, a reused ID is refused, and a stale revision conflicts (`AuthorizationAndLinkTests`, `PlaybackCommandTests`). The only destructive command, the experiment's Reset, needs `commitDestructive`, so a companion (an `authorizedPeer`) or a model tool cannot run it; the companion link was refused in the app (`theCompanionLinkSteersButCannotReset`). The page asks before Reset, which removes only the experiment's resume-point file.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No DRM extraction or conversion of arbitrary streaming URLs into downloadable media.

**Research:** [S41](../docs/SOURCE_INDEX.md#s41).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-031's spec now claims `implemented`. The screening ran in package tests on the Mac and in the tvOS simulator, in hosted tests inside the Mac, iPhone (simulator), and Apple TV (simulator) apps, and with the Siri Remote in the tvOS simulator. Nothing here is device-verified.

**The design, and why.** Playback is live session state with one authority, the device that owns the player, so it is not a stored domain operation (docs/ARCHITECTURE.md, live session transport; no LabDomain or LabStore change, so no schema version is taken). `ScreeningSession` is the one place it changes. People and controllers send `PlaybackCommand`s, authorized with LabDomain's `ActorScope`, adapter ceilings, and grants and answered once per request ID with a `PlaybackReceipt`; the system and the player send `PlaybackSignal`s, which only the owning host can deliver. The resume point (clip, position, captions) is the one durable thing: one JSON file in the experiment's own folder, which Reset removes.

**Cross-device hookup for LAB-019.** No networking was built. A controller on another device reaches the session only through `ScreeningLink` (a snapshot, or one command with a request ID and the revision it saw), and the receiving host runs it as an `authorizedPeer`, which cannot reset. `InProcessScreeningLink` stands in for the transport inside one app, labeled as a simulation on the page. LAB-019 supplies a `ScreeningLink` over its paired session and calls `ScreeningRoomModel.admit(_:)` on the receiving side; the envelope mapping is in [DATA_CONTRACTS](../docs/DATA_CONTRACTS.md#screening-commands-and-the-resume-point-lab-031).

**Changed:**

- `Packages/LabFeatures`:
  - `ScreeningRoom` (new product and target, Foundation and LabDomain only): `ScreeningRoom`, `ScreeningClips`, `MediaAsset`, `SubtitleTrack`, `CaptionChoice`, `PlaybackFailure`, `PlaybackState`, `PlaybackSurface`, `RouteChange`, `PlaybackCommand`, `PlaybackSignal`, `CommandSource`, `PlaybackRequest`, `PlaybackReceipt`, `ScreeningSession`, `ScreeningError`, `PlaybackDenial`, `ResumePoint` with `FileResumePointStore` and `MemoryResumePointStore`, and `ScreeningLink`, `ScreeningConductor`, and `InProcessScreeningLink`.
  - `ScreeningRoomPlayback` (new product and target): `BundledClips`, `ClipOpener`, `CaptionMatcher`, `ScreeningPlayer`, `AudioSessionSignals` and `AudioSessionObserver` (iOS, tvOS), `NowPlayingAdapter` (iOS, macOS), `PlayerSurfaceView` and `RoutePickerButton`, `PlaybackReadiness`, and `ScreeningRoomModel`; the three clips and `clips.json` as resources.
  - Tests (new): `ScreeningRoomTests` (40 in 5 suites) and `ScreeningRoomPlaybackTests` (19 in 4 suites). `LabCatalogTests` now expect 7 implemented and 41 specified.
- `Fixtures/LAB-031/` (new): the generator and the README with sizes, hashes, captions, and how to regenerate.
- `Apps/Shared/ScreeningRoom/` (new): `ScreeningRoomHost`, the iPhone and iPad page, the shared views, the theater presentation, the Reset confirmation, and `ScreeningRoomLaunch`.
- `Apps/Mac/Window/ScreeningRoomColumns.swift` (new) and `Apps/TV/ScreeningRoom/ScreeningRoomScreen.swift` (new).
- Hooks in shared host files, one case each:
  - `MainWindowState`: `.screeningRoom`. `MainWindow`: its two columns. `SidebarView`: its row. `LabCommands`: View › Native Screening Room (⌘9).
  - `ExperimentDetailView`: `ScreeningRoomLaunch`.
  - TV: `TVHost.runnableExperiments`; `ExperimentDetailScreen`'s Open button and "Runs here" note for LAB-031; `CatalogScreen`'s summary sentence; `LabTVApp`'s comment.
- `project.yml` and the regenerated project (XcodeGen 2.46.0 on the development Mac; research has no XcodeGen):
  - LabMac, LabPhone, LabPhoneSurfaces, and LabTV link `ScreeningRoom` and `ScreeningRoomPlayback`; LabMacTests, LabPhoneTests, and LabTVTests depend on them.
  - `UIBackgroundModes: [audio]` on LabPhone, LabPhoneSurfaces, and LabTV, which Picture in Picture needs.
  - LabTV's Store-lane purpose strings gain camera and microphone, because it now links AVFoundation (the policy's `purpose` rule); a Source build declares none.
  - The LabTV scheme's test action runs `ScreeningRoomTests` and `ScreeningRoomPlaybackTests` in the tvOS simulator.
- `Config/ProductPolicy.txt`: AVKit, CoreMedia, and MediaPlayer for CoreLocal on macOS; AVKit, AVFAudio, CoreMedia, and MediaPlayer for CoreLocal and SystemSurfaces on iOS; AVFoundation, AVKit, AVFAudio, CoreMedia, and CryptoKit (through LabDomain) for Companions on tvOS. The release manifest shows each one linked. `Config/PurposeStrings.xcconfig`: its comment.
- Tests in the hosts (new): `Tests/LabMacTests/ScreeningRoomHostTests.swift` (5), `Tests/LabPhoneTests/ScreeningRoomPhoneTests.swift` (1), `Tests/LabTVTests/ScreeningRoomTVTests.swift` (2), and `Tests/LabTVUITests/ScreeningRoomRemoteUITests.swift` (1, remote-driven).
- `experiments/LAB-031-native-screening-room.md` (`state: implemented`, the implemented split, and implementation notes) and the regenerated catalog JSON; `docs/DATA_CONTRACTS.md` (screening commands and the resume point); `docs/VERIFICATION_BOUNDARIES.md` (the installed SDK ledger's LAB-031 section); this record and rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** The installed headers were read for every adapter symbol; the findings are in the ledger. Two shaped the design: `updatesNowPlayingInfoCenter` is unavailable on tvOS, and the audio-session interruption notification is deprecated in the 27 SDKs for replacements that exist only from 27.0.
2. **Original sample media.** Three clips drawn from code: a 10-second test card with English (SDH) and Spanish subtitle tracks, a clip relabeled with an unknown codec, and a truncated file. 61 KB together, byte-identical across two runs.
3. **Native controls and remote commands.** The system's player views on every platform. On iPhone and the Mac, Now Playing and remote commands are the lab's, so they become commands with receipts; on Apple TV the system player answers the remote and the session sees signals.
4. **Caption and track selection.** The page's picker and the system menu change the same selection; options are matched by language and SDH, and forced-only variants are left out.
5. **Picture in Picture and AirPlay.** Allowed in the system player views where `PlaybackReadiness` reads them as supported, entered only from the system's own controls, and reported back as surfaces. The AirPlay route picker is on the Mac and iPhone pages.
6. **Tests.** The domain operation (`PlaybackCommandTests`), cancellation and stale state (a stale revision conflicts; a clip that finishes opening after another was chosen is dropped; a damaged resume point is ignored), invalid input (`invalidInputIsRefusedAndNothingIsRecorded`, the resume-point forms), and the unavailable path (`ClipOpenerTests`, the failing clips in the hosted tests, and `PlaybackReadiness` on each platform).

**Bug found and fixed.** The remote-driven tvOS test found that after Watch in Theater and Menu, Spanish captions had turned off: the system player re-applied the system's caption preference when it took the player. The player now has `appliesMediaSelectionCriteriaAutomatically` off, and `CaptionAuthorityTests` pins it. The cost is that the system's "Closed Captions + SDH" preference is not applied when a clip first opens.

**Commands and results:** the LAB-031-A rows in [BUILD_STATUS](../docs/BUILD_STATUS.md). `python3 script/validate/all.py` passed 8 of 8. The full `script/test.sh` stopped at its Mac step on 5 share-ingress tests that cannot read their fixtures from a mirror on research's scratch SSD (an environment problem, not this branch); every other step passed with those 5 skipped.

**Not run:**

- Any physical device. Only the integrator installs to devices.
- A real interruption, call, alarm, or unplugged output; the classic notification on a 27 device.
- Picture in Picture and AirPlay used by a person. The tvOS simulator reads Picture in Picture as unsupported.
- Control Center, the Lock Screen, headphones, and media keys.
- A hand walkthrough of the Mac and iPhone pages, iPad layouts, VoiceOver, Voice Control, Full Keyboard Access, and large text.
- Protected content: no fixture exists, and none will be made.
- A paired companion device (LAB-019), and a 26-SDK compile.

**Known limitations:** the system caption preference is not applied at first open (above); the Apple TV resume point lives in Caches, which the system may clear; the Mac theater is a sheet, because `AVPlayerView` has no call to enter full screen (its own full-screen button still works and is reported); on Apple TV, Up from the caption row skips the one-button Watch in Theater row unless focus is on its left.

**Next dependency-ready tickets:** LAB-031-B (Native Screening Room qualification), whose other prerequisites (CORE-007, CORE-009, CORE-010) are done. LAB-018-A (Together Mode) and LAB-034-A (Television Stage) wait for LAB-019-A.
