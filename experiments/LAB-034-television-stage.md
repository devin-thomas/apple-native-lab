---
id: "LAB-034"
title: "Television Stage"
state: "specified"
milestone: "M3"
category: "Media"
depends_on: ["LAB-019", "LAB-031"]
source_review: "2026-09-29"
---

# LAB-034 — Television Stage

## The moment

Turn the TV into a stage with a user-chosen phone camera and a separate controller.

## Scope and native leverage

**Hosts:** Apple TV 4K second generation or later for the camera sample; paired camera device.

**Primary APIs:** tvOS AVKit Continuity Camera, Network transport. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** StageSession, CameraRole, ControllerRole. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Run a native tvOS scene with focus navigation
2. Connect a camera through the system picker
3. Show a local-camera stage and countdown
4. Pair an independent controller over LAN

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Camera disconnect leaves an actionable TV screen.
- [ ] Focus never becomes trapped on the preview.
- [ ] Phone camera-role conflict is detected before AR starts.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

One phone cannot be assumed to supply independent simultaneous ARKit and Continuity Camera sessions. Baseline TV generation must be confirmed.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Native TV display plus a synthetic camera fixture.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/television-stage/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-034-A.md) → [qualification ticket](../tickets/LAB-034-B.md).

**Lab dependencies:** [LAB-019](LAB-019-local-constellation.md), [LAB-031](LAB-031-native-screening-room.md).

**Primary-source references:** [S27](../docs/SOURCE_INDEX.md#s27). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
