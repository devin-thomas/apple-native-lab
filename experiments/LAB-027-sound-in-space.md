---
id: "LAB-027"
title: "Sound in Space"
state: "specified"
milestone: "M3"
category: "Audio"
depends_on: ["LAB-023"]
source_review: "2026-09-29"
---

# LAB-027 — Sound in Space

## The moment

Move a sound behind a virtual wall and hear the scene change while inspecting the sound graph.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac; output-device capabilities checked.

**Primary APIs:** PHASE, AVAudioEngine, optional headphone motion. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** AudioScene, SoundEmitter, ListenerPose. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Use original sounds at safe initial volume
2. Add emitter position and occluding geometry
3. Offer a binaural/channel-aware rendering path
4. Enable compatible head tracking only when available

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Switching output route preserves safe gain.
- [ ] Missing headphones disables only head tracking.
- [ ] No double-spatialization configuration is silently accepted.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

This is an app-owned spatial mix, not global control over music from other apps.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Stereo mix and visible scene controls.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/sound-in-space/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-027-A.md) → [qualification ticket](../tickets/LAB-027-B.md).

**Lab dependencies:** [LAB-023](LAB-023-tabletop-reality.md).

**Primary-source references:** [S23](../docs/SOURCE_INDEX.md#s23), [S24](../docs/SOURCE_INDEX.md#s24). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
