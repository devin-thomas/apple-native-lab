---
id: "LAB-029-B"
title: "Qualify and document Audio Workshop"
status: "done"
milestone: "M3"
kind: "qualification"
depends_on: ["LAB-029-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-029-B — Qualify and document Audio Workshop

## Goal

Prove Audio Workshop on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-029-audio-workshop.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** audio-workshop tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: No allocation or blocking I/O in render callbacks; Output route and sample-rate changes recover; Plugin state round-trips across host reload
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] No allocation or blocking I/O in render callbacks.
- [ ] Output route and sample-rate changes recover.
- [ ] Plugin state round-trips across host reload.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** Mac and iPhone/iPad; AUv3 target isolated.

**Unavailable path:** Offline audio-file processing and on-screen MIDI events.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-029 stays `implemented`.** Four records in `evidence/LAB-029/`: two fixture checks, a Mac hosted fixture replay, and an iPhone simulator hosted replay. No physical device, live audio output, microphone, or Core MIDI source was opened. The real AVAudioEngine ran in offline manual rendering; its configuration event was injected. The plugin was registered and loaded in-process, not discovered as an AUv3 extension. Nothing is device-verified or release-ready.

**What a person can do.** Follow the [walkthrough](../docs/walkthroughs/LAB-029-audio-workshop.md) to inspect and change the original graph, send on-screen MIDI, render or process an original WAVE, save/load a preset with a receipt, and reload the in-process unit's state. It names the live-output action separately and explains that Panic Mute affects live playback, not offline exports. Workshop and global demo resets preserve saved user presets and selected source-file bytes.

**Acceptance, with proof boundaries:**

- [x] No allocation or blocking I/O in the C render path: `check_realtime.py` compiled the actual kernel clean and rejected temporary `malloc`/`free` and `fopen` render-helper mutations with `nonblocking` errors. This is compile-time C enforcement only. Swift render closures, an upstream unit's pull callback, runtime allocation traces, and device deadlines remain unqualified.
- [x] Sample-rate recovery: package tests and both hosted replays. The new replay rebuilt the real manual engine from 44.1 to 96 kHz once, retaining gain, cutoff, mute and bypass and producing silence while muted. Package tests also prove fade-in and failed-recovery fallback. Configuration events were injected: a real output-route change remains not-run.
- [x] Plugin state across host reload: package and both hosted replays create a new in-process unit and restore its preset. Package tests also compare canonical state bytes and retain settings for damaged state. No AUv3 extension or third-party host was loaded.
- [x] Toolchain, inputs, adapter and limitations: all four records. Xcode 27.0 (27A266a), Swift 6.4, macOS 27.0 (26A425), Apple M5 Max; iPhone 18 Pro simulator, iOS 27.0 (24A434). Both host replays have identical preset and original WAVE hashes: `1432556d…` and `dafaff4e…` respectively; the original file has 4,800 stereo frames at 48 kHz.
- [x] The walkthrough distinguishes simulation/manual rendering/in-process hosting from physical audio, MIDI and AUv3 loading. It makes no live-integration or accessibility qualification claim for the hosted session replay.
- [x] Publication-safe inputs: only repository-synthesized loops/signals, neutral preset names and `not audio` as invalid bytes. Reviewed the retained JSON records: no private paths, serials, accounts, store contents or real media. No screenshot, recording or WAVE export is included in the change.

**Failures and state cases:** `PresetStoreTests` proves model-tool denial, pre-cancelled save with no receipt, duplicate request returning the original receipt, and an archived destination refusing a new save. `OfflineProcessorTests` proves cancelled render returns nothing; WAVE/preset tests refuse malformed, oversized and newer inputs. `LivePlaybackTests` proves failed recovery retains the offline fallback, injected interruption handling, and a stale configuration event while stopped does not start playback. The new host replay processes a file without changing it, refuses an invalid file while retaining the prior result, saves through the real SQLite library with an app-UI receipt, retries one operation request without duplication, and verifies both resets retain the original file and user preset item. Preset loading keeps panic mute. Pressing Save again after a successful save is a new request, not a retry.

**Accessibility, rights and privacy review:** added Audio Workshop's manual-flow matrix and open findings to [ACCESSIBILITY_REVIEW](../docs/ACCESSIBILITY_REVIEW.md). Existing Mac hosted tests passed the safety buttons' accessibility press actions and menu shortcuts. Native labels, spoken slider units, combined graph summaries, accessibility-size safety layout and save announcements exist in source. Offline/error/plugin announcements, cancellation focus, manual keyboard/assistive technology, large text/contrast and iPad layouts remain unverified. Playback and MIDI are explicit actions; this run never enables them against hardware, records, uploads, or connects an account.

**Source correction:** the installed SDK still matches the earlier ledger. Repeated the C effect probe with blocking I/O as well as allocation. Corrected the qualification notes: the audio-unit Swift callback prepares preallocated buffer descriptors and invokes upstream pull before entering C; it is not wholly a one-line trampoline. Clang does not check Swift closures, and the 26-family toolchain builds without the attribute. The current stats explanation in the UI still overstates that coverage; recorded as an open finding, not changed here. Consulted Apple's AVAudioEngine and AUAudioUnit.fullState primary documentation via its documentation JSON after the Markdown fetch could not be read.

**Changed:** the identical `AudioWorkshopQualificationTests.swift` in `Tests/LabMacTests/` and `Tests/LabPhoneTests/`; `Fixtures/LAB-029/check_realtime.py` and fixture README; four evidence records; walkthrough; the Audio Workshop accessibility section and installed-SDK note; experiment qualification notes; BUILD_STATUS evidence rows; this completion record. No app implementation, shared host hook, project.yml, generated project, entitlement, capability descriptor or catalog change. The experiment state is unchanged, so no catalog regeneration was needed.

**Commands and results:** all builds/tests ran through `labr`; see the LAB-029-B rows in [BUILD_STATUS](../docs/BUILD_STATUS.md). Narrow package: 71/71. Narrow Mac: 10/10 with no skip or failure at `fc010a0`; attachment exported from `build/LAB-029-B-mac.xcresult`. Full gate at `fc010a0-dirty`: validators 8/8, validator self-tests 93, packages 97/187/61/40/119/939, and Mac host passed (198 tests: 194 passed, 3 skipped, 1 expected failure). iPhone: 12 passed, 1 failed; Audio Workshop's replay Passed and attached its record, but `SpeechTimelinePhoneTests.theOnDeviceRouteOrItsStatedFallbackRunsInsideTheApp()` failed with `Crash: NativeLab`, ending the gate with exit 65. No LAB-032 flake occurred, so no rerun was needed. The gate created/deleted only its own iPhone simulator. Watch, TV and release manifest were not reached and are not claimed. No unrelated source was patched. Final `python3 script/validate/all.py` passed all 8 validators (58 evidence records); local `git diff --check` passed.

**Diagnostic corrections:** research has no `rg`; repeated the SDK header search with `grep`. An initial result-bundle lookup used `Run-` instead of Xcode's `Test-` prefix and found no bundle; listing and reading the actual bundles succeeded. No result was inferred from either unsuccessful query.

**Not run / lead gates:** any physical iPhone/iPad, real speaker playback, real route/sample-rate change, AVAudioSession interruption/media reset, Core MIDI source/hot-plug, AUv3 extension discovery/view/automation or third-party host; manual VoiceOver, Voice Control, Full Keyboard Access, contrast/large-text/iPad layout; system file dialogs and export; runtime realtime sanitizer; Xcode 26 compile; Store-lane manifest. The -A ticket's Store-lane extension-purpose-string limitation remains. A release needs owner/device and extension-host runs, manual accessibility, and resolution of the unrelated Speech Timeline gate failure.

**Next dependency-ready ticket:** [LAB-019-B](LAB-019-B.md), whose implementation and CORE-007/009/010 prerequisites are done in this checkout.
