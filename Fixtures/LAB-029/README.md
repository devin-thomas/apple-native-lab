# LAB-029 Audio Workshop fixtures

Audio Workshop bundles no audio. Every sound it plays, renders, or tests is synthesized from code in this repository, so there is no recording to license, inventory, or leak. Nothing here was captured from a microphone, an audio interface, or another app.

## The original loops

The kernel (`Packages/LabFeatures/Sources/AudioWorkshopDSP/WorkshopKernel.c`) synthesizes three two-second loops at 120 BPM, at whatever sample rate the output runs:

| Loop | What it is | Peak |
|---|---|---|
| Pulse | Eight plucked sine notes (A3, C♯4, E4, A4, E4, C♯4, A3, E3), one per eighth note, each with a 3 ms attack and a 90 ms decay | about -10 dBFS |
| Chords | Four three-note sine chords (A minor, F, C, G), half a second each, with 10 ms fades | about -10 dBFS |
| Noise and Thump | Noise bursts from a 32-bit xorshift generator with a fixed seed, over a 55 Hz sine thump on each beat | about -6 dBFS |

The noise generator is reseeded at the start of every loop, so a loop is identical every time it plays, and two renders of the same preset at the same rate are identical to the bit. `KernelTests` and `OfflineProcessorTests` check that.

## Test signals

The package tests synthesize their inputs in `Tests/AudioWorkshopTests/TestSupport.swift`: sines, constants, and the loops above. They are small (at most a few seconds at 48 kHz) and exist only in memory. The hosted Mac tests write one rendered loop to a temporary folder to process it as a file, then delete the folder with the test.

## Hostile inputs

The hostile WAVE files and presets are built byte by byte inside the tests rather than stored, so each case states exactly what is wrong:

- WAVE (`WaveFileTests`): not RIFF, no format chunk, no data chunk, a data size past the end of the file, 6 channels, an 8-bit or ADPCM encoding, a block alignment that does not match, a 1 kHz rate, no samples, a format chunk too short, an extensible format with an unknown subformat, and files over the length and byte limits.
- Presets (`PresetTests`): not JSON, not an object, a duplicate key, another format, a newer or fractional schema version, unknown fields including `bypass`, missing fields, a Boolean where a number belongs and the reverse, out-of-range values, an unmappable controller, channel 17, an inverted range, and an oversized document.

## Saved presets

A saved preset is an item in the person's own `Audio Workshop Presets` collection, in the `user` namespace, with the preset in the item's extras under `audioWorkshopPreset` ([DATA_CONTRACTS](../../docs/DATA_CONTRACTS.md#audio-workshop-presets)). Reset Demo does not touch it. The collection's ID, `76573EDC-03EC-43E3-B1EA-A1122CAA5CF6`, was generated once at random; never reuse it.

## Qualification probe

`check_realtime.py` compiles the actual C kernel with the installed SDK, then compiles two temporary copies with `malloc`/`free` and `fopen` added to a render helper. It requires clang to reject both with `nonblocking` diagnostics. Temporary files and diagnostics stay under `build/LAB-029-B-probe`; no allocation or file open executes. This is compile-time C enforcement, not a Swift-trampoline or device-deadline trace. Run it on the build host through `labr`.
