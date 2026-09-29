---
id: "LAB-028"
title: "Recognize Our Audio"
state: "specified"
milestone: "M2"
category: "Audio"
depends_on: ["LAB-013"]
source_review: "2026-09-29"
---

# LAB-028 — Recognize Our Audio

## The moment

Play an original reference clip anywhere and let a second screen find the matching point.

## Scope and native leverage

**Hosts:** Supported iPhone/iPad/Mac; microphone input separately gated.

**Primary APIs:** ShazamKit SHCustomCatalog, AVAudioEngine. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** AudioSignatureCatalog, MatchedCue. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Build a catalog from rights-cleared fixture audio
2. Attach time-indexed cue metadata
3. Match from explicit microphone capture
4. Debounce repeated matches and expose no-match state

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] No-match does not trigger a cue.
- [ ] A repeated match cannot spam side effects.
- [ ] Stopped capture releases the microphone.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Exact prerecorded-audio matching, not a general sound classifier or live-song understanding.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Select reference clip and time manually.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/recognize-our-audio/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-028-A.md) → [qualification ticket](../tickets/LAB-028-B.md).

**Lab dependencies:** [LAB-013](LAB-013-speech-timeline.md).

**Primary-source references:** [S25](../docs/SOURCE_INDEX.md#s25), [S26](../docs/SOURCE_INDEX.md#s26). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
