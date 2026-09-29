---
id: "LAB-026"
title: "Camera Instrument Panel"
state: "specified"
milestone: "M3"
category: "Spatial"
depends_on: ["LAB-012"]
source_review: "2026-09-29"
---

# LAB-026 — Camera Instrument Panel

## The moment

Show segmentation, OCR, and simple pose landmarks as instruments with visible confidence and frame timing.

## Scope and native leverage

**Hosts:** iPhone/iPad; Mac uses selected frames or available camera.

**Primary APIs:** AVFoundation, Vision, Core Image. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** FrameObservation, ProcessingBudget. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Choose one analysis mode at a time
2. Downsample with a documented budget
3. Show evidence overlays in app
4. Drop old frames rather than build a lagging queue

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Backpressure limits queue depth.
- [ ] Permission denial keeps sample-frame inspection usable.
- [ ] No person identity or sensitive trait is inferred.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Not access to camera streams owned by another app and not an always-recording assistant.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Original sample frames and explicit image import.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/camera-instrument-panel/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-026-A.md) → [qualification ticket](../tickets/LAB-026-B.md).

**Lab dependencies:** [LAB-012](LAB-012-point-inspect-propose.md).

**Primary-source references:** [S55](../docs/SOURCE_INDEX.md#s55), [S41](../docs/SOURCE_INDEX.md#s41). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
