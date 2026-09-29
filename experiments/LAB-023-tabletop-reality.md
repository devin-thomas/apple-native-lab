---
id: "LAB-023"
title: "Tabletop Reality"
state: "specified"
milestone: "M3"
category: "Spatial"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-023 — Tabletop Reality

## The moment

Place a small interactive system on a real table, move around it, and inspect occlusion and tracking quality.

## Scope and native leverage

**Hosts:** ARKit-supported iPhone/iPad; non-AR Mac viewer.

**Primary APIs:** ARKit, RealityKit. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** WorldAnchor, SceneState, TrackingStatus. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Acquire a plane with coaching UI
2. Place original procedural objects
3. Persist only supported mapping data with consent
4. Recover from relocalization failure

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Tracking loss suspends precision interactions.
- [ ] A reset destroys only lab-owned anchors.
- [ ] An accessibility list exposes every meaningful object.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Handheld AR, not headset passthrough or guaranteed persistent world tracking.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Orbitable 3D scene with mouse/touch controls.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/tabletop-reality/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-023-A.md) → [qualification ticket](../tickets/LAB-023-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S40](../docs/SOURCE_INDEX.md#s40). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
