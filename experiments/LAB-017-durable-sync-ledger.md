---
id: "LAB-017"
title: "Durable Sync Ledger"
state: "specified"
milestone: "M3"
category: "Continuity"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-017 — Durable Sync Ledger

## The moment

Edit offline on two devices, reconnect, and explain exactly how the final state was chosen.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac; companion state distribution separately.

**Primary APIs:** CloudKit, CKSyncEngine, local transactional store. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** MutationEnvelope, VersionVector, ConflictRecord. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Maintain a local write-ahead mutation ledger
2. Sync private/shared records in an optional service profile
3. Surface conflicts instead of silently overwriting
4. Test account switching and disabled iCloud

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Conflicting edits remain inspectable.
- [ ] Deleting and reinstalling does not resurrect tombstoned data accidentally.
- [ ] Account A data never appears in account B.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

CloudKit synchronization is opportunistic, not a low-latency event bus. Never sync personal fixtures to a public database.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Local store plus manual document exchange.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/durable-sync-ledger/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-017-A.md) → [qualification ticket](../tickets/LAB-017-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S15](../docs/SOURCE_INDEX.md#s15). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
