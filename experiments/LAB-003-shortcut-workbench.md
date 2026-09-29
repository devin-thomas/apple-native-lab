---
id: "LAB-003"
title: "Shortcut Workbench"
state: "specified"
milestone: "M2"
category: "System surfaces"
depends_on: ["LAB-001", "LAB-008"]
source_review: "2026-09-29"
---

# LAB-003 — Shortcut Workbench

## The moment

Turn the lab into a small typed automation toolbox, not a collection of launch-app commands.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac.

**Primary APIs:** AppIntents, Shortcuts, 27-generation Storage actions. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** RecipeDefinition, TypedActionContract, JobHandle. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Offer a curated entry set separate from atomic actions
2. Build import-query-transform-export recipe walkthroughs
3. Persist entity references in a user-created shortcut
4. Inspect data passed into optional model steps

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] A recipe survives renaming its source item.
- [ ] Cancellation does not leave half an import.
- [ ] Raw secret values never enter recipe exports.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Up to ten curated App Shortcuts is not a ten-action library cap. Platform packaging differs; never auto-install a personal automation.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Manual recipe instructions and app action browser; no secret storage inside Shortcuts.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/shortcut-workbench/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-003-A.md) → [qualification ticket](../tickets/LAB-003-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md), [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S03](../docs/SOURCE_INDEX.md#s03), [S04](../docs/SOURCE_INDEX.md#s04). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
