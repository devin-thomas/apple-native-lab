---
id: "LAB-040"
title: "Commerce Without Tricks"
state: "specified"
milestone: "M4"
category: "Commercial"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-040 — Commerce Without Tricks

## The moment

Exercise buy, restore, refund, pending approval, and offline entitlement states using test products.

## Scope and native leverage

**Hosts:** StoreKit-supported iPhone/iPad/Mac/TV targets independently.

**Primary APIs:** StoreKit 2, StoreKit configuration tests. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** PurchaseState, VerifiedEntitlement. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Start exclusively with local StoreKit configuration
2. Present truthful product names and terms
3. Verify transaction state before entitlement
4. Exercise restore and revocation

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] No button in the default build creates a real charge.
- [ ] Unverified transactions grant nothing.
- [ ] Restoration does not require a private developer account.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

The lab itself stays free; shipping commerce requires current policy review and appropriate product classification.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Local transaction-state simulator.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/commerce-without-tricks/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-040-A.md) → [qualification ticket](../tickets/LAB-040-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S46](../docs/SOURCE_INDEX.md#s46). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
