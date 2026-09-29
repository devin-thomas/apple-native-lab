---
id: "LAB-045"
title: "Ink Has Structure"
state: "specified"
milestone: "M4"
category: "Interaction"
depends_on: ["LAB-008", "LAB-035"]
source_review: "2026-09-29"
---

# LAB-045 — Ink Has Structure

## The moment

Annotate an object and keep the ink as editable data rather than flattening everything to a screenshot.

## Scope and native leverage

**Hosts:** iPad/Pencil optional; touch on iPhone and pointer on Mac.

**Primary APIs:** PencilKit, native document APIs. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** InkLayer, AnnotationAnchor. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Draw on original sample media
2. Persist editable ink with document IDs
3. Provide erase/undo and semantic text alternatives
4. Export flattened preview separately from native data

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Undo preserves anchoring after document resize.
- [ ] Non-Pencil users complete the task.
- [ ] Unsupported pencil gestures are absent, not broken.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No iPad purchase required; advanced Pencil hardware features remain hardware-gated.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Mouse/touch annotations and typed notes.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/ink-has-structure/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-045-A.md) → [qualification ticket](../tickets/LAB-045-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md), [LAB-035](LAB-035-access-as-a-superpower.md).

**Primary-source references:** [S53](../docs/SOURCE_INDEX.md#s53). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
