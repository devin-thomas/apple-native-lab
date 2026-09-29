---
id: "LAB-022"
title: "Proximity Instrument"
state: "specified"
milestone: "M4"
category: "Spatial"
depends_on: ["LAB-019", "LAB-021"]
source_review: "2026-09-29"
---

# LAB-022 — Proximity Instrument

## The moment

Watch an instrument respond to measured distance, confidence, and unavailable direction—not invented radar.

## Scope and native leverage

**Hosts:** Participating UWB-capable devices; per-role distance/direction check.

**Primary APIs:** NearbyInteraction. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** RangingSample, TrackingQuality. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Exchange session tokens through authenticated transport
2. Probe distance and direction separately
3. Render a confidence-aware instrument
4. Stop when the session loses authorization or foreground eligibility

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Direction-not-supported never renders a compass arrow.
- [ ] Signal loss freezes no misleading current distance.
- [ ] No nearby stranger is tracked without joining.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No AirTag inventory, Find My database access, or assumption that Watch ranging equals phone ranging.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Manual distance slider or prerecorded synthetic measurements, prominently labeled.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/proximity-instrument/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-022-A.md) → [qualification ticket](../tickets/LAB-022-B.md).

**Lab dependencies:** [LAB-019](LAB-019-local-constellation.md), [LAB-021](LAB-021-wrist-relay.md).

**Primary-source references:** [S18](../docs/SOURCE_INDEX.md#s18). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
