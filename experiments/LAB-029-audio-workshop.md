---
id: "LAB-029"
title: "Audio Workshop"
state: "specified"
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

## Delivery

[Implementation ticket](../tickets/LAB-029-A.md) → [qualification ticket](../tickets/LAB-029-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S41](../docs/SOURCE_INDEX.md#s41), [S56](../docs/SOURCE_INDEX.md#s56). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
