---
id: "LAB-025"
title: "Object Forge"
state: "specified"
milestone: "M3"
category: "Spatial"
depends_on: ["LAB-008", "LAB-032"]
source_review: "2026-09-29"
---

# LAB-025 — Object Forge

## The moment

Scan an everyday object, inspect reconstruction failures, and share a viewable 3D artifact.

## Scope and native leverage

**Hosts:** Supported iPhone capture and supported Mac/device reconstruction.

**Primary APIs:** RealityKit Object Capture, PhotogrammetrySession. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** CaptureSet, ReconstructionJob, ModelAsset. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Capture consented photographs with a quality checklist
2. Validate reconstruction availability separately
3. Run a cancellable reconstruction
4. Review scale, holes, and rights before USDZ export

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Reflective/textureless objects have an explained failure path.
- [ ] Cancel preserves usable source photos.
- [ ] Output scale is labeled known or uncalibrated.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Scanning and reconstruction are separate gates. No claim that every Mac or every material reconstructs well.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Original procedural sample mesh and a supplied consented photo fixture.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/object-forge/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-025-A.md) → [qualification ticket](../tickets/LAB-025-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md), [LAB-032](LAB-032-render-that-survives.md).

**Primary-source references:** [S21](../docs/SOURCE_INDEX.md#s21), [S22](../docs/SOURCE_INDEX.md#s22). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
