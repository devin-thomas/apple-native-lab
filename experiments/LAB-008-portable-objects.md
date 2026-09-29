---
id: "LAB-008"
title: "Portable Objects"
state: "specified"
milestone: "M1"
category: "Sharing"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-008 — Portable Objects

## The moment

Drag a rich lab object into another window or export it as a inspectable document.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac.

**Primary APIs:** Transferable, UTType, document import/export. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** LabDocument v1, RepresentationDescriptor. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Provide native document, JSON, text, and URL representations where meaningful
2. Show an export preview with fields and destination
3. Validate imports before committing
4. Preserve unknown fields in a versioned extras map

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Unicode and empty optional fields round-trip.
- [ ] A path-traversal attachment is rejected.
- [ ] Reimporting one document does not duplicate stable items.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Transfer representations are adapters, not automatic clipboard parity on every platform.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

File picker and explicit export preserve the full native document.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/portable-objects/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-008-A.md) → [qualification ticket](../tickets/LAB-008-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S11](../docs/SOURCE_INDEX.md#s11), [S12](../docs/SOURCE_INDEX.md#s12). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
