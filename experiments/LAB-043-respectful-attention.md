---
id: "LAB-043"
title: "Respectful Attention"
state: "specified"
milestone: "M3"
category: "System surfaces"
depends_on: ["LAB-004"]
source_review: "2026-09-29"
---

# LAB-043 — Respectful Attention

## The moment

Compare an ordinary reminder, an app Focus filter, and a user-authorized alarm without spamming the system.

## Scope and native leverage

**Hosts:** iPhone primary; supported Mac/Watch behavior separate.

**Primary APIs:** UserNotifications, Focus filters, AlarmKit. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** AttentionRequest, FocusScope, AlarmState. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Preview when and why attention is requested
2. Schedule app-owned notifications or alarm only by consent
3. Filter only lab content for a selected Focus
4. Provide one cancel-all-lab-alerts action

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Denied permissions do not trigger repeated prompts.
- [ ] Timezone changes retain intended date semantics.
- [ ] Cancel removes only lab-owned schedules.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No entitlement bypass, automatic global Focus switching, or general control of Clock alarms.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

In-app agenda and timers visible while foregrounded.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/respectful-attention/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-043-A.md) → [qualification ticket](../tickets/LAB-043-B.md).

**Lab dependencies:** [LAB-004](LAB-004-surface-deck.md).

**Primary-source references:** [S33](../docs/SOURCE_INDEX.md#s33), [S01](../docs/SOURCE_INDEX.md#s01). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
