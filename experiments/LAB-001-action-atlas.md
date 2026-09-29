---
id: "LAB-001"
title: "Action Atlas"
state: "specified"
milestone: "M1"
category: "System surfaces"
depends_on: []
source_review: "2026-09-29"
---

# LAB-001 — Action Atlas

## The moment

Create a collection, find an item, mutate it, and inspect the same receipt from three entry points.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac; Watch adapter later.

**Primary APIs:** AppIntents, AppEntity, entity queries. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** LabItem, Collection, ActionReceipt. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Seed 12 original sample objects with stable UUIDs
2. Expose create/find/update/archive/export intents
3. Call the same operation from UI and Shortcuts
4. Show typed output and undo receipt

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Duplicate request IDs cause one mutation.
- [ ] Missing and ambiguous entities produce recoverable errors.
- [ ] UI and intent yield identical persisted state.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

AppEntity is not arbitrary access to other apps. Domain operations remain authorization-checked.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

A normal app action browser runs without Siri or Apple Intelligence.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/action-atlas/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-001-A.md) → [qualification ticket](../tickets/LAB-001-B.md).

**Lab dependencies:** none beyond the core foundation.

**Primary-source references:** [S01](../docs/SOURCE_INDEX.md#s01), [S03](../docs/SOURCE_INDEX.md#s03), [S05](../docs/SOURCE_INDEX.md#s05). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
