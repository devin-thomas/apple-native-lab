---
id: "LAB-036"
title: "Workout Session Mirror"
state: "specified"
milestone: "M4"
category: "Watch"
depends_on: ["LAB-021"]
source_review: "2026-09-29"
---

# LAB-036 — Workout Session Mirror

## The moment

Observe a clearly consented test workout on Watch and phone while preserving a fully synthetic learning mode.

## Scope and native leverage

**Hosts:** Watch and paired iPhone; health-capable target.

**Primary APIs:** HealthKit workout sessions and mirroring. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** WorkoutSample, MirroredSessionState. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Default to synthetic samples
2. Request narrow health access only for live mode
3. Start a real user-requested workout
4. Mirror session controls and stop cleanly

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] No denied health field is treated as zero.
- [ ] Live samples cannot enter public fixtures.
- [ ] Stop ends the actual workout session.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No medical conclusions or fake workouts used as a background entitlement workaround.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Synthetic replay supports the complete UI without HealthKit access.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/workout-session-mirror/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-036-A.md) → [qualification ticket](../tickets/LAB-036-B.md).

**Lab dependencies:** [LAB-021](LAB-021-wrist-relay.md).

**Primary-source references:** [S43](../docs/SOURCE_INDEX.md#s43), [S19](../docs/SOURCE_INDEX.md#s19). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
