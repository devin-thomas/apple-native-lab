---
id: "LAB-012"
title: "Point, Inspect, Propose"
state: "specified"
milestone: "M3"
category: "Intelligence"
depends_on: ["LAB-007", "LAB-010"]
source_review: "2026-09-29"
---

# LAB-012 — Point, Inspect, Propose

## The moment

Inspect an object or screenshot and turn observations into a reviewable lab record.

## Scope and native leverage

**Hosts:** Supported iPhone; iPad/Mac camera-import fallback.

**Primary APIs:** Vision, Foundation Models image input, Visual Intelligence integration. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** Observation, ImageEvidence, CaptureConsent. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Begin with a user-selected image
2. Run deterministic OCR/barcode where suitable
3. Offer a model-generated interpretation with image provenance
4. Add optional supported system visual-search participation

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Barcode payloads cannot execute actions.
- [ ] Photos containing private text remain local by default.
- [ ] Uncertain recognition stays an editable suggestion.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

System Visual Intelligence participation is not the same as arbitrary visual-agent control. Camera observation is not identity recognition.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Image picker plus OCR and manual fields.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/point-inspect-propose/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-012-A.md) → [qualification ticket](../tickets/LAB-012-B.md).

**Lab dependencies:** [LAB-007](LAB-007-share-ingress-station.md), [LAB-010](LAB-010-typed-local-intelligence.md).

**Primary-source references:** [S06](../docs/SOURCE_INDEX.md#s06), [S55](../docs/SOURCE_INDEX.md#s55), [S62](../docs/SOURCE_INDEX.md#s62). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
