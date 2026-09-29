---
id: "LAB-021"
title: "Wrist Relay"
state: "specified"
milestone: "M2"
category: "Watch"
depends_on: ["LAB-001", "LAB-019"]
source_review: "2026-09-29"
---

# LAB-021 — Wrist Relay

## The moment

Tap a small wrist control and see a durable acknowledgement, even when delivery must wait.

## Scope and native leverage

**Hosts:** Paired iPhone and Watch; Mac/TV receive through a separate link.

**Primary APIs:** WatchConnectivity, watchOS SwiftUI, system haptics. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** WristCommand, AckState, CompanionSnapshot. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Use immediate messages only when reachable
2. Use queued transfer for durable events
3. Show pending, acknowledged, failed, and expired states
4. Keep complications glanceable and safe when locked

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Ten repeated transport deliveries produce one mutation.
- [ ] A haptic acknowledgement is not shown before the intended stage.
- [ ] Unreachable phone retains a bounded queue.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

The Watch is not an always-on streaming process; no fake workout session to keep it alive.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Phone control pad and a Watch simulator preview.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/wrist-relay/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-021-A.md) → [qualification ticket](../tickets/LAB-021-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md), [LAB-019](LAB-019-local-constellation.md).

**Primary-source references:** [S19](../docs/SOURCE_INDEX.md#s19). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
