---
id: "LAB-029-A"
title: "Implement Audio Workshop"
status: "done"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-029-A — Implement Audio Workshop

## Goal

Build a tiny usable audio processor with a inspectable graph, MIDI control, and an optional plugin form.

## Authority and scope

Read the [governing specification](../experiments/LAB-029-audio-workshop.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** audio-workshop module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Start with gain/filter and original loops
3. Make bypass and panic-mute always reachable
4. Map one MIDI parameter
5. Package a separate AUv3 only after standalone validation
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] No allocation or blocking I/O in render callbacks. (Compile-time proof, not a runtime trace. Every render callback is one call into the C kernel, whose render path carries clang's `nonblocking` attribute (the SDK's `CA_REALTIME_API`), and `WorkshopKernel.c` makes clang's function-effect diagnostics errors. A copy of the kernel with `malloc` and `free` injected into the render path failed to compile with "function with 'nonblocking' attribute must not call non-'nonblocking' function 'malloc'"; the real kernel compiles clean with `-Wall -Wextra` and in every build of the gate. The kernel allocates all of its memory in `AWKKernelCreate`, and the audio unit allocates its pull buffers in `init`. The Swift trampolines that call it capture only raw pointers and are formed outside any actor; clang does not check them, and Xcode 27.0 has no RealtimeSanitizer runtime.)
- [x] Output route and sample-rate changes recover. (Simulated notification, real engine. `LivePlaybackTests` and the hosted `playbackRecoversFromASampleRateChangeKeepingMuteAndSettings` run AVAudioEngine in offline manual rendering, report a configuration change from 44.1 to 48 kHz and from 48 to 96 kHz, and check that the graph is rebuilt at the new rate with one recovery, fades in from silence with no sample-to-sample jump over 0.05, and keeps gain, cutoff, panic mute, and bypass. A rate that will not start fails after three attempts with a reason, and offline rendering still works. No real route change, device, or `AVAudioSession` notification was observed.)
- [x] Plugin state round-trips across host reload. (In-process host only. `AudioUnitTests.pluginStateRoundTripsAcrossAHostReload` and the hosted `theAudioUnitReloadsWithItsStateInTheApp`, in the sandboxed Mac app, instantiate `WorkshopAudioUnit` through `AVAudioUnit.instantiate`, set a preset, save `fullState` as binary property-list data, drop the unit, instantiate a new one, and restore it: the new instance reports the same preset and the same canonical preset bytes. A damaged state keeps the current preset. No third-party host loaded the AUv3 extension.)
- [x] Fallback is usable: Offline audio-file processing and on-screen MIDI events. (`OfflineProcessorTests` and the hosted `offlineRenderingAndFileProcessingWorkWithoutLiveOutput`: with no live output, Play says live audio is unavailable and points at the fallback; Render the Loop Offline gives a deterministic 32-bit float WAVE file, and Process a WAVE File… runs a file written to disk through the same graph, refusing a non-WAVE file with its reason and keeping the previous result. The on-screen controller sends the same MIDI 1.0 bytes a hardware controller would, through the same parser and mapping (`onScreenMidiMovesTheCutoffThroughTheSameParser`, `MidiTests`).)
- [x] Sensitive operations share the domain authorization/receipt path. (The workshop's one change to the lab's data is Save Preset: one `createItem` in the person's preset collection, created on first save, through `LabLibrary.submit`, `LabDataService.perform`, and `OperationService.perform` as the app UI, with a receipt whose undo archives it (`PresetStoreTests`, hosted `aPresetIsSavedWithAReceiptListedAndLoadedBack`). A retry returns the original receipt with one copy saved, a model-tool actor is refused, an archived collection, an empty name, and a cancelled save commit nothing. Playback, MIDI, offline renders, and the audio unit change no stored data and need no grant. Nothing records.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No automatic gain jumps, phantom-power control, or promise of compatibility with every proprietary audio interface.

**Research:** [S41](../docs/SOURCE_INDEX.md#s41), [S56](../docs/SOURCE_INDEX.md#s56).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

**State claimed: implemented.** The graph, its safety controls, MIDI mapping, offline fallback, presets, and the hosted audio unit ran on the Mac, with live output exercised through AVAudioEngine's offline manual rendering. The iPhone hosts and the AUv3 extension compiled for the iOS 27.0 simulator; neither was run there. No audio device was opened, nothing played through a speaker, nothing was recorded, and no MIDI client was created. Nothing is device-verified. The branch is `ticket/LAB-029-A`; integration is pending.

**What a person can do.** Open Audio Workshop from its catalog page, the Mac sidebar, or View › Audio Workshop (⌘9). Play one of three original loops (Pulse, Chords, Noise and Thump) through a low-pass filter and a gain stage, and inspect the graph: each stage, its settings, and whether it is active. Panic Mute and Bypass are always in reach: pinned at the bottom of the iPhone page, at the top of the Mac workshop, and in the Lab menu with ⇧⌘M and ⇧⌘B (Play is ⇧⌘P). Move the cutoff from a MIDI controller (CC 74 by default, any channel, 80 Hz to 12 kHz) or from the on-screen controller, which sends the same bytes. Render the loop offline or process a WAVE file and export the result. Save the graph as a preset, with a receipt, and load it back. Load the filter as an audio unit, save its state, and reload it. Reset Workshop returns the experiment to its first run and keeps saved presets.

**Design.**

- **The kernel is C.** The 27.0 SDKs mark their new realtime-safe render block types unavailable in Swift ("Swift is not supported for use with audio realtime threads") and annotate render blocks with `CA_REALTIME_API`, which is clang's `nonblocking` attribute. So the whole render path is C with that attribute, and clang's function-effect diagnostics are errors in that file. Swift reaches it through one-line trampolines that capture only the kernel's pointer, built outside any actor so no main-actor check runs on the audio thread.
- **Parameters live in the kernel**, as atomics. Every control, MIDI message, and audio unit parameter writes them directly, with no lock. Gain, mute, bypass, the filter switch, and the cutoff are ramped or glided, so nothing jumps. Every prepare, at start and after a recovery, fades in from silence. A safety limit holds samples within full scale and counts them, and a non-finite sample becomes silence and clears the filter.
- **Panic mute and bypass are not preset content.** Loading a preset cannot unmute the output or change bypass; only a person's Unmute clears mute.
- **The domain operation** is Save Preset: one `createItem` in the person's `Audio Workshop Presets` collection, whose ID is fixed so every save finds it ([DATA_CONTRACTS](../docs/DATA_CONTRACTS.md#audio-workshop-presets)). The preset is the item's extras; the note is a readable summary. Presets are user data, so Reset Demo never touches them, and the receipt's undo archives.
- **The AUv3 extension** (`AudioWorkshopUnit`, SystemSurfaces) serves the same `WorkshopAudioUnit` and kernel, embedded only by `LabPhoneSurfaces`. CoreLocal carries no extension. The Mac has no AUv3: macOS needs it inside a Mac app, and there is no Mac SystemSurfaces host variant. The Mac app hosts the same unit in-process instead.

**Changed:**

- `Packages/LabFeatures`:
  - `AudioWorkshopDSP` (new C target): `WorkshopKernel.c` and `include/AudioWorkshopDSP.h`.
  - `AudioWorkshop` (new target and product), depending on AudioWorkshopDSP and LabDomain: `AudioWorkshop`, `LoopFixture`, `WorkshopParameter`, `AudioKernel`, `KernelHandle`, `RenderStats`, `AudioGraphPreset`, `PresetRejection`, `MidiEvent`, `MidiByteParser`, `UniversalMidi`, `MidiMapping`, `AudioGraph`, `GraphNode`, `WaveFile`, `PCMAudio`, `OfflineProcessor`, `PresetStore`, `PresetBackend`, and `PresetSaveRequest`. On iOS and macOS only: `LivePlayback`, `AudioOutput`, `EngineOutput`, `ManualRenderingOutput`, `MidiInput`, `WorkshopAudioUnit`, and `PluginHost`.
  - `AudioWorkshopTests` (new): 71 tests in 8 suites (`KernelTests`, `PresetTests`, `MidiTests`, `WaveFileTests`, `OfflineProcessorTests`, `PresetStoreTests`, `LivePlaybackTests`, `AudioUnitTests`).
  - `LabCatalogTests` now expect 7 implemented and 41 specified experiments.
- `Apps/Shared/AudioWorkshop/` (new): `AudioWorkshopSession` (one per process), `LibraryPresetBackend`, the shared sections, the iPhone page, and `AudioWorkshopLaunch`.
- `Apps/Mac/Window/AudioWorkshopColumns.swift` (new).
- `Extensions/AudioWorkshopUnit/` (new): `AudioUnitViewController` and its generated Info.plist.
- `Tests/LabMacTests/AudioWorkshopHostTests.swift` (new): 9 hosted tests.
- Hooks in shared host files, one case each:
  - `MainWindowState`: `.audioWorkshop`. `MainWindow`: its columns. `SidebarView`: its row.
  - `LabCommands`: View › Audio Workshop (⌘9), and Play, Panic Mute, and Bypass in the Lab menu (⇧⌘P, ⇧⌘M, ⇧⌘B).
  - `ExperimentDetailView`: `AudioWorkshopLaunch`.
- `project.yml` and the regenerated project:
  - LabMac, LabPhone, and LabPhoneSurfaces link `AudioWorkshop`.
  - New target `AudioWorkshopUnit` (iOS app extension, `com.apple.AudioUnit-UI`, `AudioComponents` with `sandboxSafe`), embedded only by `LabPhoneSurfaces` and built by `LabPhone-Surfaces`. The scheme now names `LabPhoneSurfaces` as its run executable: build targets are listed alphabetically, and the extension would otherwise have become the scheme's runnable.
  - No entitlement, no Info.plist key on a host, and no purpose string were added.
- `Config/ProductPolicy.txt`: AVFAudio, AudioToolbox, and CoreMIDI for CoreLocal on macOS and iOS and for SystemSurfaces on iOS, and CoreAudioKit for SystemSurfaces on iOS. `Config/Profiles/SystemSurfaces.xcconfig`: the attached targets.
- `Fixtures/LAB-029/README.md` (new). No audio is bundled.
- `experiments/LAB-029-audio-workshop.md`: `state: implemented`, the implemented split, and implementation notes; the catalog JSON was regenerated. `docs/DATA_CONTRACTS.md`: Audio Workshop presets. `docs/VERIFICATION_BOUNDARIES.md`: the installed SDK ledger rows. `docs/SOURCE_INDEX.md`: S41 and S56 notes. `docs/BUILD_AND_DISTRIBUTION.md` and `docs/BUILD_STATUS.md`: the scheme and profile rows, and the evidence rows.

**Implementation steps:**

1. **Probe.** The 27.0 SDK headers for AVFAudio, AudioToolbox, CoreAudioTypes, CoreAudioKit, and CoreMIDI were read on research; the symbols and availability are in the [installed SDK ledger](../docs/VERIFICATION_BOUNDARIES.md#audio-graph-audio-unit-and-midi-lab-029). A probe compile showed clang accepts `sinf`, `tanf`, `expf`, `powf`, and C11 atomics in a `nonblocking` function and refuses `malloc`, `free`, and static locals.
2. **Gain, filter, and original loops.** Three synthesized loops, an RBJ low-pass biquad, and a ramped gain.
3. **Bypass and panic mute always reachable.** See above; both survive a recovery and a preset load.
4. **One MIDI parameter.** A controller sets the cutoff exponentially. MIDI 1.0 bytes with running status, and Universal MIDI Packets of both protocols, are parsed; Core MIDI input opens only when a person turns it on.
5. **AUv3 after standalone validation.** The extension came last, around the same class the hosted tests had validated.
6. **Tests.** The domain operation (`PresetStoreTests`), cancellation (a cancelled offline render and a cancelled save), invalid input (formats, parameters, presets, MIDI, WAVE files, oversized render calls, non-finite samples), and the unavailable path (no live output; a recovery that cannot restart).

**Bugs found and fixed in the runs:**

- The sandboxed Mac app could not instantiate the in-process audio unit (`OSStatus -3000`), although a test process could. The component description now carries `kAudioComponentFlag_SandboxSafe`.
- A unit's parameters are 32-bit floats, so a preset applied to it with a resonance of 1.8 reports 1.7999999523. The round-trip tests compare what the unit reports before and after the reload.
- `JSONSerialization` wrote a resonance of 0.9 as `0.90000000000000002`, which the data-contract test caught in the full gate. The canonical form now uses `JSONEncoder`, which writes each number in its shortest exact form.

**Gate:** `LAB_SIMULATOR_PREFIX="NL LAB-029-A" script/test.sh` through `labr` passed, including the release manifest for CoreLocal, SystemSurfaces, and Companions. The extension links AVFAudio, AudioToolbox, CoreAudioKit, CoreMIDI, and the base frameworks, and is signed with only `application-identifier`.

**Evidence:** the LAB-029-A rows of the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Not run:**

- Any physical device, and any real audio output: live playback was never started against a device, by design of this ticket.
- A real route or sample-rate change, an `AVAudioSession` interruption, or media-services reset. Each was simulated against the real engine.
- A MIDI source, hot-plugging, and Core MIDI in the sandboxed Mac app: no MIDI client was created.
- The AUv3 extension in any host app, on the simulator or a device, and its view. It was compiled only.
- The iPhone page in the simulator, VoiceOver, Voice Control, iPad layouts, a 26-SDK compile, and `build_manifest.py --lane Store`.

**Known limitations:**

- The Swift render trampolines are outside clang's check, and there is no runtime allocation trace.
- The audio unit ignores MIDI and ramped parameter events in its render; a host maps MIDI to its parameters, and the kernel smooths every change.
- In the Store lane, the extension links AVFAudio, which `Config/ProductPolicy.txt` ties to `NSMicrophoneUsageDescription`, though it never records. The Store manifest would fail it until a decision is made.
- ⌘9, ⇧⌘P, ⇧⌘M, and ⇧⌘B are new shortcuts. They did not collide in this build's `noTwoCommandShortcutsCollide`, but other open branches may also claim ⌘9.

**Next dependency-ready ticket:** LAB-029-B (qualification). It needs this ticket and CORE-007, CORE-009, and CORE-010. Its first jobs: load the AUv3 extension in a host, observe a real route and rate change, and run on a device.
