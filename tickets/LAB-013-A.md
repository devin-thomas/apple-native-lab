---
id: "LAB-013-A"
title: "Implement Speech Timeline"
status: "done"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-013-A — Implement Speech Timeline

## Goal

Record or import speech and scrub a time-aligned transcript that improves while you watch.

## Authority and scope

Read the [governing specification](../experiments/LAB-013-speech-timeline.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** speech-timeline module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Request recording only after an explicit start
3. Separate provisional text from finalized segments
4. Handle required model downloads transparently
5. Export original audio reference and text timing
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Route changes do not silently lose the session.
  - Audio route: `routeChangesDoNotSilentlyLoseTheSession` replays a scripted capture that finalizes one segment, shows a guess, then reports "the audio device in use was disconnected". The session pauses and says so, keeps the finalized segment, removes the unfinalized guess and counts it, and ignores anything after the change. Resume starts the next run at the timeline's end (1,700 ms), so the resumed segment follows the first one without overlap.
  - `anInterruptionPausesAndAFailureKeepsTheSegments` does the same for a system interruption and a failed run.
  - Navigation: the session is one model for the app (`SpeechTimelineModel.shared`), not view state, so leaving the experiment and returning keeps it. No test drives that navigation.
  - Not shown: the live capture's route and interruption observers. They compile and have never run, because this build's Record falls back before capture (see Not run).
- [x] Final segments do not duplicate provisional text.
  - `finalSegmentsDoNotDuplicateProvisionalText` replays the update sequence the transcriber produced on the development Mac and checks, after every update, that no guess overlaps a finalized segment and that "Water" appears once. `aFinalResultClosesTheGuessItCovers`, `aGuessForFinalizedAudioIsDropped`, and `aRepeatedFinalIsIgnoredAndAnOverlappingOneIsRefused` cover the edges.
  - Live, on the development Mac: 41 provisional snapshots and 4 final segments, and no snapshot showed a guess over finalized audio (`evidence/LAB-013/speech-timeline-live-mac.json`). The sandboxed Mac app's live run also ended with no provisional text.
  - Saving and both exports carry finalized segments only (`onlyFinalizedSegmentsAreSavedAndAnEmptyTimelineIsNot`, `webVTTExportRoundTripsTimesAndCorrectedText`).
- [x] Transcript corrections preserve the original media timestamps.
  - `correctionsPreserveTheOriginalMediaTimestamps`: the corrected segment keeps its range, its word times, its recognized text ("2nd"), and its source; scrubbing to its audio still finds it; revert restores it exactly. A refused correction changes nothing.
  - The live Mac run corrected a real segment and its range did not move. The hosted Mac fallback test corrected a caption and its range did not move.
  - Both exports and the saved item keep `range` and `recognized` beside the corrected text (`theTimelineExportKeepsAudioReferenceTimesAndSources`, `savingCommitsOneItemAsTheAppUIWithAReceipt`).
- [x] Fallback is usable: Import a caption fixture or annotate manually; unsupported languages are stated..
  - In the package, `anUnavailableTranscriberLeavesTheFallbackUsable` imports the caption fixture, corrects a cue, annotates by hand, and saves with a receipt, with the transcriber not compiled and unavailable.
  - In the sandboxed Mac app, `theFallbackCompletesTheInteractionWithoutTheTranscriber` does the same through the host model and `LabLibrary`, and `theUnavailablePathIsStatedAndTheCaptionFallbackCompletesThroughAccessibility` renders the views: it reads "On-device transcription is not available on this device.", finds Speak and Transcribe the Sample, Record, and Import Audio… disabled, presses Import Sample Captions through the accessibility API, and reads each segment labeled "Imported caption (not recognition)".
  - In the iOS 27.0 simulator the real transcriber is unavailable. The iPhone app's `theOnDeviceRouteOrItsStatedFallbackRunsInsideTheApp` loaded the bundled captions, spoke the sample with the device's synthesizer, and got the stated `transcriberUnavailable` failure with nothing transcribed.
  - Unsupported languages: `unsupportedLanguagesAreStatedAndNothingIsTranscribed` names "tlh" as "not supported for on-device transcription on this device", and a supported language without its model as downloadable, never downloaded by transcription. The language picker always offers the fixtures' language and the device's own, so an unsupported one is stated rather than hidden.
- [x] Sensitive operations share the domain authorization/receipt path.
  - Saving is one `createItem` through `LabLibrary.submit` and `OperationService` as the app UI. The hosted test's receipt is committed, joins the inspector's list, and is returned again for a second press of Save, which adds no second item. In the package, a model tool's save is refused as outside its adapter ceiling (`theModelToolCannotSaveATranscript`).
  - The microphone is asked for only from Record, through `PermissionStager` (`nothingAsksForTheMicrophoneUntilRecordIsPressed`: zero requests after reading languages, transcribing, importing captions, annotating, and exporting; one after Record). A refusal is not asked again, and a build without the purpose string or entitlement never asks. In the Mac app, Record fell back with "This build does not declare NSMicrophoneUsageDescription, so the lab does not ask for the microphone." and never reached capture.
  - A model download starts only from its Download button: `noSourceReachesAServerOrTheOlderRecognizer` fails if any source other than the installer asks for an installation, or if any source uses `SFSpeechRecognizer`, `URLSession`, or `Network`.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No assumption of speaker identification, perfect names, or access to calls/other apps audio.

**Research:** [S10](../docs/SOURCE_INDEX.md#s10).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-013's spec now claims `implemented`. On-device transcription ran on the development Mac, in a test process and in the sandboxed app, on speech the Mac's own synthesizer produced. The unavailable path and the caption fallback ran on the Mac and in the iOS 27.0 simulator, where the transcriber is unavailable. Nothing here is device-verified, and no microphone was opened.

**Changed:**

- `Packages/LabFeatures/Package.swift`: the `SpeechTimeline` product and target, and `SpeechTimelineTests`. It depends on LabDomain and LabSupport.
- `Packages/LabFeatures/Sources/SpeechTimeline/` (new):
  - The domain types: `MediaTimeRange` (whole milliseconds, end exclusive), `TranscriptSegment` with `SegmentID`, `SegmentSource`, and `TimedWord`, `ProvisionalText`, and `TranscriptTimeline` with `RecognizerUpdate` and `UpdateOutcome`.
  - `CaptionDocument` (WebVTT in and out), `TimelineExport` with `AudioReference`, and `TranscriptSave` with the `SpeechTimelineBackend` a host provides.
  - `RecordingGate` over LabSupport's `PermissionStager`, `RecordingSession`, and `CaptureEvent`.
  - `SpeechTimelineFlow`, and the adapters: `OnDeviceSpeechRecognizer`, `OnDeviceModelInstaller`, `OnDeviceSpeechCapture`, and `SampleClipRenderer`.
  - `SpeechFixture` and the limits.
- `Packages/LabFeatures/Tests/SpeechTimelineTests/` (new): 45 tests in 7 suites. One of them, `LiveSpeechEvidenceTests`, is skipped unless `LAB_LIVE_SPEECH=1`.
- `Apps/Shared/SpeechTimeline/` (new): `SpeechTimelineModel` (one for the app), `LibrarySpeechBackend`, the experiment folder, a metadata-only diagnostics log, and the views, including `SpeechTimelineEntry` for the catalog page.
- `Apps/Mac/Window/SpeechTimelineColumns.swift` (new).
- Shared host files, one hook each:
  - `MainWindowState`: a `speechTimeline` destination with its title and storage key.
  - `SidebarView`: one row.
  - `MainWindow`: the content and detail cases.
  - `ExperimentDetailView`: one line for the entry.
  - iPhone gets no tab. No View-menu shortcut was added, to avoid clashing with parallel branches.
- `project.yml` and the regenerated project: LabMac, LabPhone, and LabPhoneSurfaces link `SpeechTimeline` and bundle the script and the caption fixture. No new entitlement or Info.plist key.
- `Config/ProductPolicy.txt`: CoreLocal on macOS and iOS, and SystemSurfaces on iOS, may link AVFAudio, for the synthesizer, playback, and the capture engine. The first `script/test.sh` run's release manifest failed without these lines. Speech, AVFoundation, and CryptoKit were already allowed.
- `Fixtures/speech/` (new): the script, the caption fixture, two refused caption files, and a README with their hashes. No audio.
- `Tests/LabMacTests/SpeechTimelineHostTests.swift` and `SpeechTimelineViewTests.swift`, and `Tests/LabPhoneTests/SpeechTimelinePhoneTests.swift` (new).
- `experiments/LAB-013-speech-timeline.md`: `state: implemented`, the implemented split, and implementation notes. The Fallback paragraph is unchanged. The catalog JSON was regenerated, and `ExperimentCatalogTests` and `ExperimentRegistryTests` now expect seven implemented experiments.
- `docs/SOURCE_INDEX.md` (S10), the [installed SDK ledger](../docs/VERIFICATION_BOUNDARIES.md#speech-lab-013), [DATA_CONTRACTS](../docs/DATA_CONTRACTS.md#speech-timelines-lab-013), `evidence/LAB-013/`, and rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** The macOS, iOS, and tvOS 27.0 Speech interfaces were read, and a throwaway program on the development Mac transcribed synthesized speech before any lab code was written. The findings are in the ledger and the spec's implementation notes. The transcriber needed no permission prompt for a file, and `AssetInventory.status(forModules:)` said `.supported` for a model `installedLocales` listed and that worked.
2. **Recording only after an explicit start.** Record is the only caller of `RecordingGate.decide()`, which is the only caller of `PermissionStager` here.
3. **Provisional apart from final.** `TranscriptTimeline`'s rules, shown in italics and never saved or exported.
4. **Model downloads.** The language's state is stated beside the picker. A supported language without its model offers Download Model, which calls `AssetInventory.assetInstallationRequest(supporting:)` and shows its progress. Transcription never downloads. No download was run.
5. **Export.** WebVTT captions and the timeline JSON, through the system save panel. The JSON names the audio by SHA-256 and origin, never by name or path. Save to Collection keeps the same export in the item's extras.
6. **Tests.** The domain operation (`SaveTests`), cancellation (`cancellingKeepsTheFinalizedSegmentsAndDropsTheGuess`: returns within 400 ms, keeps the finalized segment, drops the guess), invalid input (ranges, text, captions, exports), and the unavailable path (package, Mac host, rendered view, and the iPhone app in the simulator).

**Live runs:**

| Where | Result |
|---|---|
| `swift test` process on the development Mac (Apple M5 Max, macOS 27.0), `LAB_LIVE_SPEECH=1` | passed. The synthesizer spoke the 4-line script as a 7,373 ms clip; the transcriber gave 41 provisional snapshots and 4 segments with 25 word times: "The kettle clicked off at 7.", "Blue tape marks the 2nd shelf.", "Water the fern on Thursday.", "The spare key is in the green tin." Transcription took 390 ms in the recorded run. `evidence/LAB-013/speech-timeline-live-mac.json` |
| Sandboxed Mac app, hosted test with `TEST_RUNNER_LAB_LIVE_SPEECH=1` | passed: at least 3 on-device segments, a 64-character audio hash, provisional text shown before the segments were final, and a save with an app-UI receipt. 1.1 s for the test |
| iOS 27.0 simulator, package test | blocked: `SpeechTranscriber.isAvailable` false and no languages. `evidence/LAB-013/speech-timeline-live-ios-simulator.json` |
| iOS 27.0 simulator, inside the iPhone app | passed: the synthesizer spoke the sample (about 9 s in one measured run), and transcription failed with the stated unavailable reason |

These are single runs, not a benchmark. The audio is synthesized speech, not a person.

**Commands run:** listed in the LAB-013-A rows of [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Not run:**

- A physical iPhone or iPad, and any device where the transcriber is available other than the development Mac.
- A microphone. The source builds declare no microphone purpose string and the Mac build has no `com.apple.security.device.audio-input` entitlement, so Record falls back; `OnDeviceSpeechCapture`, its route-change and interruption observers, and a real route change have never run.
- A model download.
- Real voices, rooms, and languages other than en-US.
- The iPhone screens driven in the simulator: only the hosted phone test ran there.
- VoiceOver, Voice Control, and Full Keyboard Access passes.
- A 26-family SDK compile.

**Known limitations:**

- Reset is the experiment's own: Reset Speech Timeline removes its folder (the synthesized clip and the imported-audio copy) and the session on screen. The lab-wide Reset Demo does not call it, to keep this ticket's hooks in shared files to one case each.
- A recording keeps no audio, so it can be scrubbed as text but not played back, and its audio reference has no hash.
- Saving again after a correction adds a new item: the store writes an item's extras once, at creation.
- The caption fixture's times are approximate against the synthesized clip, whose own times depend on the device's voice.
- The WebVTT reader is small: no regions, styles, or nested cue timestamps.

**Needs the lead:**

- `project.yml` changed, and the regenerated project is committed (`script/generate_project.sh` on research with its XcodeGen 2.46.0). `Config/ProductPolicy.txt` gained three AVFAudio `link` lines.
- Live recording needs an owner decision: the microphone purpose string in source builds, and `com.apple.security.device.audio-input` for the Mac host in `Config/ProductPolicy.txt` and its entitlements. Until then Record states why it is closed.
- The catalog tests' counts (seven implemented) will conflict with any branch that also changes a state.

**Next dependency-ready ticket:** LAB-013-B, which needs this ticket, CORE-007, CORE-009, and CORE-010 (all done). LAB-028-A and LAB-014-A wait on LAB-013-B; LAB-033-A also waits on LAB-032-B.
