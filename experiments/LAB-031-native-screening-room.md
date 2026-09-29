---
id: "LAB-031"
title: "Native Screening Room"
state: "specified"
milestone: "M2"
category: "Media"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-031 — Native Screening Room

## The moment

Watch a rights-cleared clip, switch native playback surfaces, and resume without losing position or captions.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac, Apple TV.

**Primary APIs:** AVPlayer, AVKit, Now Playing, PiP/AirPlay where supported. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** MediaAsset, PlaybackState, SubtitleTrack. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Import or use original sample media
2. Use native playback controls and remote commands
3. Add caption/track selection
4. Probe PiP and AirPlay per platform

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Audio interruptions and route changes preserve correct state.
- [ ] Caption selection survives a presentation change.
- [ ] Unavailable codec or protected content shows a real error.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No DRM extraction or conversion of arbitrary streaming URLs into downloadable media.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

In-app local playback using a small universally supported fixture.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/native-screening-room/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-031-A.md) → [qualification ticket](../tickets/LAB-031-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S41](../docs/SOURCE_INDEX.md#s41). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
