---
id: "LAB-038"
title: "Wallet Moment"
state: "specified"
milestone: "M4"
category: "Commercial"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-038 — Wallet Moment

## The moment

Build an original event pass with a useful update story and an explicit signing boundary.

## Scope and native leverage

**Hosts:** iPhone; Watch Wallet display is system-managed.

**Primary APIs:** Wallet passes, PassKit. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** PassDefinition, PassUpdate. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Render a pass preview without signing
2. Validate the payload and barcode
3. Use an operator-supplied signing environment for a test pass
4. Inspect updates and expiration behavior

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] No pass-signing key enters a client or repo.
- [ ] A barcode is not treated as authorization by itself.
- [ ] Expired passes have an honest state.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Wallet passes are not payment credentials, government ID issuance, or unrestricted NFC/secure-element access.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Local pass preview and sample event card.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/wallet-moment/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-038-A.md) → [qualification ticket](../tickets/LAB-038-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S45](../docs/SOURCE_INDEX.md#s45). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
