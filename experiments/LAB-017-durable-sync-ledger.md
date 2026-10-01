---
id: "LAB-017"
title: "Durable Sync Ledger"
state: "implemented"
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

Implemented split (LAB-017-A):

- `Packages/LabFeatures/Sources/DurableSyncLedger/`: `MutationEnvelope`, `VersionVector`, `ConflictRecord`, the write-ahead log, `SyncLedger`, the file profile that stands in for a private or shared database, and the manual document (`native-lab-sync-ledger`, schema 1). Materializing an edit is one `OperationService` commit. The module does not import CloudKit. A deletion needs a grant (ADR-013). A model tool cannot commit (ADR-011).
- `Apps/Shared/DurableSync/`: the two-device fixture replay and the iPhone screen. The Mac reaches it from the sidebar and View › Durable Sync Ledger (⌘9), with its columns in `Apps/Mac/Window/DurableSyncColumns.swift`. The iPhone reaches it from this experiment's catalog page. Reset Demo removes only `Application Support › Native Lab › Durable Sync Ledger`.
- `Fixtures/LAB-017/`: documents the ledger refuses (a public scope, a newer schema).

## Implementation notes (LAB-017-A)

Observed with Xcode 27.0 (27A266a) and the iOS 27.0 SDK's CloudKit interface on 2026-09-30. These are package-test facts, not device proof, and not a live CloudKit sync.

- `CKSyncEngine` and `CKSyncEngine.Configuration.init(database:stateSerialization:delegate:)` are available from macOS 14.0 and iOS 17.0, under the lab's 26.0 floor, so this module has no `LAB_SDK_27` gate. `automaticallySync` exists; a future adapter must leave it false. `CKDatabase.Scope` includes `public`; this ledger's `RecordScope` does not. CoreLocal does not link CloudKit and does not declare `com.apple.developer.icloud-services`.
- The profile used here is a directory: `private/<account>/<mutation>.json` or `shared/<share>/<mutation>.json`. Account A and Account B are fixture UUIDs. Opening another account's ledger directory is refused. A private document from another account is refused.
- iCloud off is `DisabledSyncProfile`. `sync()` throws before it reads or writes the profile. Export and import of the manual document still run.
- Two devices that edit apart keep both versions. The screen shows the explanation and a button for each side. Choosing writes a new envelope whose version vector happened after both. A tombstone that dominates an older edit does not recreate the record when a new device directory replays the log.

## Delivery

[Implementation ticket](../tickets/LAB-017-A.md) → [qualification ticket](../tickets/LAB-017-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S15](../docs/SOURCE_INDEX.md#s15). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
