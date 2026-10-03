---
id: "LAB-013"
title: "Speech Timeline"
state: "implemented"
milestone: "M2"
category: "Audio"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-013 — Speech Timeline

## The moment

Record or import speech and scrub a time-aligned transcript that improves while you watch.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac subject to language/device support.

**Primary APIs:** SpeechAnalyzer, SpeechTranscriber, AssetInventory. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** TranscriptSegment, MediaTimeRange. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Request recording only after an explicit start
2. Separate provisional text from finalized segments
3. Handle required model downloads transparently
4. Export original audio reference and text timing

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [x] Route changes do not silently lose the session.
- [x] Final segments do not duplicate provisional text.
- [x] Transcript corrections preserve the original media timestamps.
- [x] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [x] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No assumption of speaker identification, perfect names, or access to calls/other apps audio.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Import a caption fixture or annotate manually; unsupported languages are stated.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/speech-timeline/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-013-A):

- `Packages/LabFeatures/Sources/SpeechTimeline/` holds everything except the views:
  - the domain types `MediaTimeRange`, `TranscriptSegment`, `ProvisionalText`, and `TranscriptTimeline`, which keeps provisional text apart from finalized segments and makes corrections that never move a segment's time;
  - `CaptionDocument` (WebVTT in and out), `TimelineExport` (`native-lab-speech-timeline`, schema version 1) with its content-addressed `AudioReference`, and `TranscriptSave`, the one `createItem` a save commits;
  - `RecordingGate` over LabSupport's `PermissionStager`, and `RecordingSession`, which pauses on a route change or an interruption and resumes on the same timeline;
  - `SpeechTimelineFlow`, and the on-device adapters: `OnDeviceSpeechRecognizer` (files), `OnDeviceSpeechCapture` (microphone), `OnDeviceModelInstaller` (the Download action), and `SampleClipRenderer` (the device's speech synthesizer).

  It depends on LabDomain and LabSupport, never holds the store, and imports Speech and AVFoundation on iOS and macOS only.
- `Apps/Shared/SpeechTimeline/` holds the one session model for the app (`SpeechTimelineModel.shared`), the host backend over `LabLibrary`, and the views.
  - The Mac reaches it from the sidebar and from this experiment's catalog page, with its columns in `Apps/Mac/Window/SpeechTimelineColumns.swift`.
  - iPhone reaches it from the catalog page only. It has no tab.
- `Fixtures/speech/` holds the script, the caption fixture, and two refused caption files. No audio is committed; see its README.

## Implementation notes (LAB-013-A)

Observed with Xcode 27.0 (27A266a), the macOS 27.0 and iOS 27.0 SDKs, and this experiment's tests on the development Mac (Apple M5 Max, macOS 27.0) and an iOS 27.0 simulator. These are compile, test, and simulator facts, not device proof.

- **Recognition path.** `SpeechAnalyzer(modules:)` with one `SpeechTranscriber(locale:transcriptionOptions:reportingOptions:attributeOptions:)`, reporting `.volatileResults` with `.audioTimeRange`. A file goes through `analyzeSequence(from:)` and `finalizeAndFinish(through:)`. Every API used is available from 26.0, so nothing is behind `LAB_SDK_27`. The 27.0 additions (`AnalyzerInputConverter`, `AssetInputSequenceProvider`, `CaptureInputSequenceProvider`) are not used.
- **Provisional and final.** On a synthesized clip the transcriber sent growing guesses over a range, then a final result for the first part of that range, then a new guess starting at the finalization time. A final result therefore removes the guess it overlaps, even when the guess ran past the final's end: the guess's text contains the finalized words. A guess that ends at or before the finalized time is dropped. The live Mac run showed no snapshot with a guess over finalized audio.
- **Numbers.** The transcriber wrote "seven" as "7" and "second" as "2nd". That is what the correction path is for; the recognized text stays beside the correction.
- **No prompt for files.** Transcribing a file needed no permission prompt: `SFSpeechRecognizer.authorizationStatus()` read "not determined" in the test process, and the sandboxed Mac app transcribed with no purpose string. Only the microphone is staged, and only from Record.
- **Assets.** `SpeechTranscriber.installedLocales` listed en-US on the development Mac, while `AssetInventory.status(forModules:)` for the same transcriber returned `.supported`, not `.installed`, and transcription worked. Readiness therefore reads `installedLocales`, as the CORE-004 probe does, and `AssetInventory` is used only for the Download action's `assetInstallationRequest(supporting:)`. No download was run.
- **The iOS 27.0 simulator.** It reports `SpeechTranscriber.isAvailable` false, so the unavailable path runs there live, while `AVSpeechSynthesizer.write` works and speaks the sample.
- **Recording.** The source builds declare no microphone purpose string, and the Mac build has no `com.apple.security.device.audio-input` entitlement, so Record falls back with that reason and never prompts. `OnDeviceSpeechCapture` compiles and has never run. It keeps no audio.
- **Sample audio.** No audio is committed. The device's own synthesizer speaks the committed script into the experiment's folder, because the system voices are not licensed for redistributing their output.
- **Navigation.** The session lives in one model for the app, not in a view, so leaving the experiment and returning keeps it.

## Qualification notes (LAB-013-B)

Qualified on the development Mac and in the iOS 27.0 simulator; no physical iPhone or iPad took part, and no microphone was opened. The state stays `implemented`. The [walkthrough](../docs/walkthroughs/LAB-013-speech-timeline.md) says what ran where.

- **A late guess over finalized audio is dropped.** A generated-stream test found that a guess delivered after a final, starting before it and running past it, was shown over the finalized segment, so its words appeared twice. `TranscriptTimeline` now drops any guess that overlaps a finalized segment, as it already dropped one wholly inside finalized audio.
- **A segment is one line, Unicode separators included.** The line and paragraph separators (U+2028, U+2029) are refused like a line break.
- **Which audio changes stop a recording is `CaptureStop`.** The capture now stops, and the session pauses and says why, on the engine's configuration change on both platforms and, on iOS, on "no suitable route for the category" as well as a device connected, a device lost, and a route configuration change. Compiled and tested as a mapping; never run on hardware.
- **The app's session.** A recording stopped by a route change, an interruption, or a failure is announced, not only shown; a Resume that cannot start names the segments it kept; a second Record press while the first waits for the gate does nothing; and a new timeline is never saved as a retry of the previous one's save.
- **The intermittent iOS host-test crash was a launch metadata trap.** Crash stacks point to `LabFocusFilterIntent.appContext`, not recognizer teardown. The Focus adapter now uses `SELF IN` against notification content filter criteria; a negative-control build with the old predicate crashes in the real context-construction regression ([ADR-LAB-013](../docs/adr/ADR-LAB-013.md)). Repeated targeted simulator runs are recorded in the qualification ticket. The unsupported speech path never creates a recognizer.
- **Live recording is blocked on an owner decision**, not failed: the microphone purpose string in the source builds and `com.apple.security.device.audio-input` for the Mac host.

## Delivery

[Implementation ticket](../tickets/LAB-013-A.md) → [qualification ticket](../tickets/LAB-013-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S10](../docs/SOURCE_INDEX.md#s10). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
