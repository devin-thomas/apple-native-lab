---
id: "LAB-005"
title: "Live Session Beacon"
state: "specified"
milestone: "M2"
category: "System surfaces"
depends_on: ["LAB-004", "LAB-032"]
source_review: "2026-09-29"
---

# LAB-005 — Live Session Beacon

## The moment

Follow a real finite export or rehearsal with a cancel button and honest progress.

## Scope and native leverage

**Hosts:** iPhone; system-mediated companion presentations probed.

**Primary APIs:** ActivityKit, WidgetKit. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** JobStatus, ProgressSnapshot. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Start from an explicit user action
2. Publish coarse monotonic progress
3. End with success, failure, or cancellation
4. Provide privacy-safe compact and expanded layouts

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] No activity remains active after terminal state.
- [ ] Unknown total work is indeterminate, not fabricated percent.
- [ ] Force-quit/relaunch restores the job truth.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

A Live Activity is not a background worker or an unlimited widget refresh loophole.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

In-app job panel and optional completion notification.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/live-session-beacon/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-005-A.md) → [qualification ticket](../tickets/LAB-005-B.md).

**Lab dependencies:** [LAB-004](LAB-004-surface-deck.md), [LAB-032](LAB-032-render-that-survives.md).

**Primary-source references:** [S58](../docs/SOURCE_INDEX.md#s58), [S28](../docs/SOURCE_INDEX.md#s28). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
