---
id: "LAB-004"
title: "Surface Deck"
state: "specified"
milestone: "M1"
category: "System surfaces"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-004 — Surface Deck

## The moment

One reversible session state appears in a widget, a Control, and the main app.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac; supported Watch surfaces.

**Primary APIs:** WidgetKit, Control widgets, AppIntents. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** SessionSnapshot, ControlState. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Build small/medium widgets from immutable snapshots
2. Expose one toggle and one launch action
3. Let users add Controls and map supported hardware triggers
4. Refresh by documented policy rather than a live polling timer

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Stale widget toggles reconcile to current state.
- [ ] Locked-device view redacts private labels.
- [ ] A denied update budget leaves a correct stale indicator.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Widget/Control availability is per platform. An iPhone Action button does not imply a Watch Action button.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Main-app state deck and static widget previews.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/surface-deck/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-004-A.md) → [qualification ticket](../tickets/LAB-004-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S01](../docs/SOURCE_INDEX.md#s01), [S59](../docs/SOURCE_INDEX.md#s59). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
