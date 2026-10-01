---
id: "LAB-031"
title: "Native Screening Room"
state: "implemented"
milestone: "M2"
category: "Media"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-031 — Native Screening Room

## The moment

Watch a rights-cleared clip, switch native playback surfaces, and resume without losing position or captions.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac, Apple TV.

**Primary APIs:** AVPlayer, AVKit, Now Playing, PiP/AirPlay where supported. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** MediaAsset, PlaybackState, SubtitleTrack. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Import or use original sample media
2. Use native playback controls and remote commands
3. Add caption/track selection
4. Probe PiP and AirPlay per platform

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Audio interruptions and route changes preserve correct state.
- [ ] Caption selection survives a presentation change.
- [ ] Unavailable codec or protected content shows a real error.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No DRM extraction or conversion of arbitrary streaming URLs into downloadable media.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

In-app local playback using a small universally supported fixture.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/native-screening-room/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-031-A):

- `Packages/LabFeatures/Sources/ScreeningRoom/`: the platform-free rules. `MediaAsset`, `SubtitleTrack`, and `CaptionChoice`; `PlaybackState` with its surface, interruption, route change, failure, and revision; `PlaybackCommand` (decisions, each authorized and answered with a `PlaybackReceipt`) and `PlaybackSignal` (what the system and the player report); `ScreeningSession`, the one place the state changes; `ResumePoint` and its file store; and `ScreeningLink`, the narrow command-and-snapshot surface a companion controller uses, with `InProcessScreeningLink` standing in for a paired transport. Foundation and LabDomain only, so it compiles on every host, the Watch included.
- `Packages/LabFeatures/Sources/ScreeningRoomPlayback/`: the adapters and the original clips. `ClipOpener` decides with AVFoundation whether a clip can play before a player sees it; `ScreeningPlayer` owns the one `AVPlayer`; `AudioSessionObserver` (iOS, tvOS) reports interruptions and route changes; `NowPlayingAdapter` (iOS, macOS) publishes Now Playing and turns remote commands into commands; `PlayerSurfaceView` wraps `AVPlayerViewController` or `AVPlayerView`; `ScreeningRoomModel` ties them together for every host; `PlaybackReadiness` says what this device offers.
- `Apps/Shared/ScreeningRoom/`: the iPhone and iPad page, the shared views, the theater presentation (a full-screen cover on iPhone and iPad, a sheet on the Mac), and the catalog page's Open button. The Mac has a Native Screening Room sidebar destination and View › Native Screening Room (⌃⌘1).
- `Apps/TV/ScreeningRoom/`: the Apple TV page, opened from the experiment's detail page, with a non-focusable preview and the system player as the theater.
- `Fixtures/LAB-031/`: the clips' generator and their record. The clips themselves are bundled from the playback target's resources.

## Implementation notes (LAB-031-A)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs, on the Mac and in the iOS and tvOS 27.0 simulators. These are compile, package-test, and simulator facts, not device proof.

- Playback is live session state, not a stored record. It changes only through `ScreeningSession`, which authorizes each command with the domain's own rules (the fixed `AdapterKind` ceilings, then the actor's grants), answers each request ID once with a receipt, conflicts on a stale expected revision, and raises the revision on every change except a position sample. The receipts stay with the session instead of the operation store (docs/ARCHITECTURE.md, live session transport). The one destructive command, the experiment's Reset (`forgetResumePoint`), needs `commitDestructive`, which an authorized peer cannot hold.
- The one durable thing is the resume point: clip, position, and captions, as one small JSON file in the experiment's own folder (Application Support on the Mac and iPhone; Caches on Apple TV, which keeps no Application Support folder and may clear it). A damaged or foreign file is ignored and reported; Reset removes that file and nothing else.
- Every surface attaches to one `AVPlayer`, so moving between the page, the theater, full screen, Picture in Picture, and AirPlay never reloads the item, and the caption selection stays in the player. The lab asks only for the page and the theater; full screen, Picture in Picture, and AirPlay start from the system's own controls, and the player views report them as signals.
- A file whose only video track has an unknown codec is "ready to play" to an `AVPlayerItem`, which then shows nothing. `ClipOpener` therefore asks the asset first (`hasProtectedContent`, `isPlayable`, each track's `isPlayable` and sample-entry code) and never hands an unplayable clip to the player. The unknown-codec fixture reads `isPlayable == false` with its track's code `lab0`; the truncated one throws AVFoundation -11829 (Cannot Open) with underlying OSStatus -12848.
- The player's automatic media selection is off (`appliesMediaSelectionCriteriaAutomatically = false`). With it on, the tvOS system player re-applied the system's caption preference when it took the player for the theater, so Spanish captions came back off; the remote-driven tvOS UI test caught it. The cost: the system's "Closed Captions + SDH" preference is not applied when a clip first opens. Captions start off, and the person chooses them in the page or the system's caption menu.
- AVFoundation derives a forced-only variant of each subtitle track, so the test card has four legible options for two tracks. Captions are matched by language and the SDH characteristics, never by the localized display name.
- The interruption notification and its keys are deprecated in the 27 SDKs in favor of `AVAudioSession.didBecomeInactiveNotification` and `resumptionRecommendationNotification`, which exist only from iOS and tvOS 27.0. The lab's floor is 26.0 and a package has no SDK compile flag, so the classic notification is used; the player's own rate-change reason (`.audioSessionInterrupted`) also reports the start of an interruption, which keeps the order of the two reports from mattering.
- On iPhone and the Mac the player views do not publish Now Playing themselves (`updatesNowPlayingInfoCenter = false`), so Control Center, the Lock Screen, headphones, and the media keys reach the session as commands with receipts. That property is unavailable on tvOS, where the system player answers the Siri Remote itself and the session sees its changes as signals.
- Picture in Picture on iPhone and iPad needs the `audio` background mode, which LabPhone, LabPhoneSurfaces, and LabTV now declare.
- A companion controller on another device is not built here: LAB-019 supplies the paired transport. The page's Companion remote runs in the same app through `InProcessScreeningLink`, as an authorized peer, and says it is a simulation.

## Delivery

[Implementation ticket](../tickets/LAB-031-A.md) → [qualification ticket](../tickets/LAB-031-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S41](../docs/SOURCE_INDEX.md#s41). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
