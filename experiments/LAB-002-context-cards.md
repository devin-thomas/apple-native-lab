---
id: "LAB-002"
title: "Context Cards"
state: "specified"
milestone: "M2"
category: "System surfaces"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-002 — Context Cards

## The moment

Ask about the visible object, then complete a small decision inside a system presentation.

## Scope and native leverage

**Hosts:** iPhone and iPad; Mac support probed separately.

**Primary APIs:** App Schemas, NSUserActivity, SwiftUI snippets. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** VisibleEntityContext, DecisionProposal. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Associate one primary sample entity with its view
2. Map only genuinely matching Apple schemas
3. Render an interactive confirmation where supported
4. Resolve stale visible content without touching a different object

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] A replaced onscreen item cannot mutate the previous item.
- [ ] A schema mismatch fails the integration gate.
- [ ] Siri-disabled devices retain the same decision UI.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No invented universal schema for arbitrary business nouns; Siri rollout and region are separate gates.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

In-app card and typed Shortcut remain complete; context resolution is explicitly unavailable.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/context-cards/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-002-A.md) → [qualification ticket](../tickets/LAB-002-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S02](../docs/SOURCE_INDEX.md#s02), [S03](../docs/SOURCE_INDEX.md#s03), [S64](../docs/SOURCE_INDEX.md#s64). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
