---
id: "LAB-030"
title: "Tactile Grammar"
state: "implemented"
milestone: "M2"
category: "Interaction"
depends_on: ["LAB-004"]
source_review: "2026-09-29"
---

# LAB-030 — Tactile Grammar

## The moment

Design three distinguishable tactile cues and compare actual device output rather than treating haptics as decoration.

## Scope and native leverage

**Hosts:** Capable iPhone, supported controllers, Watch system haptics separately.

**Primary APIs:** Core Haptics, GameController, Watch haptic APIs. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** CuePattern, DeviceHapticCapabilities. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Create success/warning/timing cues with original audio
2. Show visual and spoken equivalents
3. Route to supported device feedback
4. Provide a clear stop and intensity preference

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Unsupported actuators never crash a cue.
- [ ] Muted haptics leave every task usable.
- [ ] Repeated cues obey rate and fatigue limits.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No arbitrary custom waveform parity on Watch; controller support differs by device.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Visual pulse and optional quiet audio.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/tactile-grammar/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-030-A):

- `Packages/LabFeatures/Sources/TactileGrammar/`: the three cues (`CuePattern`), the synthesized quiet tones (`CueAudio`), the route (`CueRouter`), and `TactileGrammarEngine`. A play is authorized with the same adapter ceiling, grants, and denial reasons as `OperationService` (ADR-011). It records an immutable receipt for the request ID. A cue is not a lab entity, so the receipt stays in the engine and is not a store row, and it does not take an ADR-013 grant. A model tool may propose and cannot play. Reset Demo clears only that cue log.
- Live adapters in the same target, compiled only for the SDKs that contain them: Core Haptics and GameController on iOS, macOS, and tvOS; a quiet `AVAudioPlayer` tone on iOS and macOS; `WKInterfaceDevice.play` on watchOS. The Watch route sends one system haptic and an empty event list.
- `Apps/Shared/TactileGrammar/`: the page iPhone pushes from this experiment's catalog entry. The Mac reaches it from the sidebar and View › Tactile Grammar (⌘9). The Watch has its own page (`Apps/Watch/TactileGrammarWatch.swift`). Apple TV does not link the product.

## Implementation notes (LAB-030-A)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs. These are compile and fixture facts, not a measurement of a physical actuator.

- `CHHapticEngine` is iOS 13.0, macOS 10.15, tvOS 14.0, and `API_UNAVAILABLE(watchOS)`. The watchOS SDK has no Core Haptics framework. `capabilitiesForHardware()` and `supportsHaptics` are the capability probe. `makePlayer(with:)` is the Swift name of `createPlayerWithPattern:error:`. `CHHapticTimeImmediate` is 0.
- `GCController.haptics` and `GCDeviceHaptics.createEngine(withLocality:)` are iOS 14.0, macOS 11.0, and tvOS 14.0. `.default` is guaranteed. A controller that does not report `haptics` is not a haptic route.
- `WKInterfaceDevice.play(_:)` is watchOS 2.0. The cues map to `.success`, `.retry`, and `.start`. Navigation and underwater types are not used. There is no custom waveform on Watch.
- No entitlement is required for these reads or for playback. Quiet audio uses `AVAudioSession` category `.ambient` on iOS so the silent switch still silences the tone. The visual pulse and the spoken words remain.
- Package tests drive a stand-in actuator. They prove the fallback, muted play, rate and fatigue limits, cancellation, invalid ids, and the authorization refusals. They do not prove what a device's actuator did.
- On the research Mac (Apple M5 Max), `LiveHapticCapabilities.read()` returned Core Haptics false, controller haptics false, Watch false, and quiet audio true. The call returned. It did not play a cue.

## Delivery

[Implementation ticket](../tickets/LAB-030-A.md) → [qualification ticket](../tickets/LAB-030-B.md).

**Lab dependencies:** [LAB-004](LAB-004-surface-deck.md).

**Primary-source references:** [S49](../docs/SOURCE_INDEX.md#s49), [S50](../docs/SOURCE_INDEX.md#s50). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
