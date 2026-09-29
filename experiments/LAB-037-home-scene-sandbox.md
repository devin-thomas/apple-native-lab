---
id: "LAB-037"
title: "Home Scene Sandbox"
state: "specified"
milestone: "M4"
category: "Commercial"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-037 — Home Scene Sandbox

## The moment

Preview a home-scene diff, execute only selected harmless actions, and explain partial failure.

## Scope and native leverage

**Hosts:** iPhone/iPad; supported Mac client separately.

**Primary APIs:** HomeKit, Matter optional controller investigation. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** AccessorySnapshot, SceneProposal. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Use simulated lights first
2. Request access to the selected home
3. Preview on/off/brightness changes
4. Commit and report per-accessory outcomes

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] A disconnected lamp does not mark the whole scene successful.
- [ ] Locks, doors, alarms, and heating are excluded by default.
- [ ] A revoked home permission stops live mode.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

HomeKit does not expose every vendor API; Matter controller work is separate from a HomeKit client.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Deterministic fictional home with no real accessories.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/home-scene-sandbox/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-037-A.md) → [qualification ticket](../tickets/LAB-037-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S44](../docs/SOURCE_INDEX.md#s44). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
