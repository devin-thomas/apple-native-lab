---
id: "LAB-016"
title: "Pick Up Here"
state: "specified"
milestone: "M2"
category: "Continuity"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-016 — Pick Up Here

## The moment

Move a draft to another device and resume at the exact selected section without pretending Handoff is file sync.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac.

**Primary APIs:** NSUserActivity, Handoff, universal-link routing. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** ContinuationToken, DocumentLocator. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Advertise a small resumable activity
2. Transfer only identifiers and position
3. Resolve or request the underlying document
4. Handle a newer revision on the destination

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Missing document prompts import instead of empty success.
- [ ] Revoked access does not reveal old content.
- [ ] A changed document clamps the saved position safely.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Handoff is a continuation hint, not guaranteed bulk transfer or instant background execution.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Copy an explicit continuation link or document.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/pick-up-here/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-016-A.md) → [qualification ticket](../tickets/LAB-016-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S60](../docs/SOURCE_INDEX.md#s60). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
