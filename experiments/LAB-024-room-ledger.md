---
id: "LAB-024"
title: "Room Ledger"
state: "specified"
milestone: "M3"
category: "Spatial"
depends_on: ["LAB-023", "LAB-008"]
source_review: "2026-09-29"
---

# LAB-024 — Room Ledger

## The moment

Turn a scanned room into an editable semantic inventory and compare the scan to manual corrections.

## Scope and native leverage

**Hosts:** LiDAR-capable iPhone/iPad capture; Mac review.

**Primary APIs:** RoomPlan, RealityKit. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** RoomCapture, SpatialAnnotation, MeasurementConfidence. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Ask for camera permission at scan start
2. Capture walls/openings and coarse furniture categories
3. Attach editable notes to selected elements
4. Export a redacted model with a privacy preview

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Raw room scans never enter public artifacts.
- [ ] Unsupported scanner opens a manual floor-plan path.
- [ ] Measurement edits retain scan provenance.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Not survey-grade measurements, cable detection, or reliable identification of every device.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Bundled fictional room plus manual dimensions.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/room-ledger/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-024-A.md) → [qualification ticket](../tickets/LAB-024-B.md).

**Lab dependencies:** [LAB-023](LAB-023-tabletop-reality.md), [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S20](../docs/SOURCE_INDEX.md#s20). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
