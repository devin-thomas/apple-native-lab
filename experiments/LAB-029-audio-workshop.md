---
id: "LAB-029"
title: "Audio Workshop"
state: "implemented"
milestone: "M3"
category: "Audio"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-029 — Audio Workshop

## The moment

Build a tiny usable audio processor with a inspectable graph, MIDI control, and an optional plugin form.

## Scope and native leverage

**Hosts:** Mac and iPhone/iPad; AUv3 target isolated.

**Primary APIs:** AVAudioEngine, Audio Units, Core MIDI. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** AudioGraphPreset, MidiMapping, RenderStats. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Start with gain/filter and original loops
2. Make bypass and panic-mute always reachable
3. Map one MIDI parameter
4. Package a separate AUv3 only after standalone validation

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] No allocation or blocking I/O in render callbacks.
- [ ] Output route and sample-rate changes recover.
- [ ] Plugin state round-trips across host reload.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No automatic gain jumps, phantom-power control, or promise of compatibility with every proprietary audio interface.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Offline audio-file processing and on-screen MIDI events.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/audio-workshop/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-029-A):

- `Packages/LabFeatures/Sources/AudioWorkshopDSP/`: the realtime kernel, in C. The original loop synthesizer, the RBJ low-pass biquad with a gliding cutoff, the ramped gain, the bypass and filter crossfades, panic mute, the safety limit, and the render counters. Every function a render callback reaches carries clang's `nonblocking` attribute, and the file turns clang's function-effect diagnostics into errors.
- `Packages/LabFeatures/Sources/AudioWorkshop/`: `AudioKernel` and its `KernelHandle`, `AudioGraphPreset`, `MidiMapping` with the MIDI 1.0 byte parser and the Universal MIDI Packet reader, `RenderStats`, the inspectable `AudioGraph`, `WaveFile`, `OfflineProcessor`, and `PresetStore` over a host `PresetBackend`. On iOS and macOS only: `LivePlayback` with `EngineOutput` (AVAudioEngine) and `ManualRenderingOutput` (offline manual rendering), `MidiInput` (Core MIDI), `WorkshopAudioUnit` (the AUv3 effect), and `PluginHost`. It depends on LabDomain and never holds the store.
- `Apps/Shared/AudioWorkshop/`: `AudioWorkshopSession`, one per process, and `LibraryPresetBackend` (reads as the app UI through `LabDataService`, commits through `LabLibrary.submit`); the safety controls, graph, stats, sound, MIDI, offline, preset, and plugin sections; and the iPhone page. The Mac reaches it from the sidebar and View › Audio Workshop (⌃⌘3), with Play, Panic Mute, and Bypass in the Lab menu (⇧⌘P, ⇧⌘M, ⇧⌘B); its columns are in `Apps/Mac/Window/AudioWorkshopColumns.swift`. The iPhone reaches it from this experiment's catalog page, with the safety controls pinned to the bottom.
- `Extensions/AudioWorkshopUnit/`: the AUv3 effect extension (SystemSurfaces), embedded only by `LabPhoneSurfaces`. Its principal class creates `WorkshopAudioUnit` and shows its parameters.
- `Fixtures/LAB-029/`: a README. No audio is bundled: every loop and test signal is synthesized.

## Implementation notes (LAB-029-A)

Observed with Xcode 27.0 (27A266a), Swift 6.4, and the 27.0 SDKs on macOS 27.0. These are Mac facts and iOS simulator compiles, not device proof. No test opened an audio device: live output was exercised through AVAudioEngine's offline manual rendering.

- The 27.0 SDKs add realtime-safe render block types (`AVAudioSourceNodeRenderBlockRealtimeSafe` and others) marked `CA_REALTIME_API` and `__SWIFT_UNAVAILABLE_MSG("Swift is not supported for use with audio realtime threads")`. `CA_REALTIME_API` expands to clang's `[[clang::nonblocking]]`. So the kernel is C, and the Swift render blocks are one-line trampolines that use the older block types, capture only the kernel's pointer, and are formed outside any actor, so no main-actor check runs on the audio thread.
- Clang enforces `nonblocking` at compile time. A copy of the kernel with `malloc` and `free` injected into the render path failed to compile with "function with 'nonblocking' attribute must not call non-'nonblocking' function 'malloc'"; the kernel itself compiles clean with `-Wall -Wextra`. `sinf`, `tanf`, `expf`, `powf`, and C11 atomics are accepted. A static local variable is refused. Xcode 27.0 ships no RealtimeSanitizer runtime (`libclang_rt.rtsan*` is absent), so there is no runtime allocation check. With a toolchain that lacks the attribute (the 26 family), the same code builds unchecked.
- A route or sample-rate change stops AVAudioEngine and posts `AVAudioEngineConfigurationChange`. `LivePlayback` then prepares the kernel for the new format and starts the engine again, up to three times. Every prepare fades the output in from silence, and parameters, including panic mute and bypass, live in the kernel's atomics, so they survive a rebuild. The notification itself was simulated; the rebuild ran the real engine and source node at the new rate.
- The audio unit registered in-process was found by `AVAudioUnit.instantiate` in a test process, but not in the sandboxed Mac app (`OSStatus -3000`) until its component description carried `kAudioComponentFlag_SandboxSafe`. The extension's Info.plist declares `sandboxSafe` for the same reason.
- `fullState` carries the preset's canonical JSON under `nativeLab.audioWorkshop.preset`, beside the base class's own keys. A missing or refused preset leaves the unit's current settings unchanged. Parameters are 32-bit floats in a unit, so a round trip is exact for what the unit reports, not for the double-precision preset it was given.
- MIDI: `MIDIInputPortCreateWithProtocol` (macOS 11, iOS 14; unavailable on tvOS and watchOS) delivers Universal MIDI Packets. The CoreMIDI module in the 27.0 SDK has no Swift overlay, so packets are walked with the header's inline `MIDIEventPacketNext`. Core MIDI input only starts when a person turns on Listen to MIDI Sources; no test created a MIDI client.
- The unit does not read MIDI from its render events; a host maps MIDI to its parameters. Its render also ignores ramped parameter events: the kernel's own smoothing ramps every change.
- The Mac has no AUv3 extension: macOS needs the extension inside a Mac app, and CoreLocal may not embed one. The Mac app hosts the same unit in-process instead.

## Qualification boundaries (LAB-029-B)

The [walkthrough](../docs/walkthroughs/LAB-029-audio-workshop.md) distinguishes manual-rendering recovery and in-process state reload from physical route changes and AUv3 extension loading. [Realtime probe evidence](../evidence/LAB-029/audio-workshop-realtime-probe.json) repeats clang enforcement with both allocation and blocking-I/O mutations. Swift render closures and upstream pull callbacks are outside this check; the unit closure also prepares preallocated buffer descriptors. No runtime allocation trace or physical-device claim is made. Offline processing uses preset parameters and bypass, not live Panic Mute. Saved presets and selected source bytes are user-owned and survive reset.

## Delivery

[Implementation ticket](../tickets/LAB-029-A.md) → [qualification ticket](../tickets/LAB-029-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S41](../docs/SOURCE_INDEX.md#s41), [S56](../docs/SOURCE_INDEX.md#s56). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
