---
id: "LAB-017-A"
title: "Implement Durable Sync Ledger"
status: "done"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-017-A — Implement Durable Sync Ledger

## Goal

Edit offline on two devices, reconnect, and explain exactly how the final state was chosen.

## Authority and scope

Read the [governing specification](../experiments/LAB-017-durable-sync-ledger.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** durable-sync-ledger module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Maintain a local write-ahead mutation ledger
3. Sync private/shared records in an optional service profile
4. Surface conflicts instead of silently overwriting
5. Test account switching and disabled iCloud
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Conflicting edits remain inspectable. (`ConflictAndCausalTests.editsMadeApartStayInspectableUntilSomeoneChooses`; hosted `twoDevicesKeepApartEditsUntilAChoice`. Both sides stay as a conflict with an explanation that nothing was overwritten until a person chooses.)
- [x] Deleting and reinstalling does not resurrect tombstoned data accidentally. (`TombstoneReinstallTests.reinstallingDoesNotBringBackATombstonedRecord` and `aConcurrentEditDoesNotSilentlyResurrectADeletion`. A fresh device directory that pulls the tombstone stays deleted; an older upsert planted under the tombstone does not recreate the record.)
- [x] Account A data never appears in account B. (`AccountAndProfileTests.accountANeverAppearsInAccountB` and `openingAnotherAccountsFolderIsRefused`. A private document from another account is refused; opening another account's ledger directory throws `foreignLedger`.)
- [x] Fallback is usable: Local store plus manual document exchange.. (`AccountAndProfileTests.disabledICloudDoesNotTouchTheProfile`; hosted `disabledProfileStillExportsAndImports`. With the profile off, `sync()` throws before it reads or writes; export and import still round-trip.)
- [x] Sensitive operations share the domain authorization/receipt path. (`LedgerOperationTests.aDeletionWithoutAGrantCommitsNothing` and `aModelToolCannotCommit`. Materializing is one `OperationService` commit; a deletion needs a grant; a model tool cannot commit.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** CloudKit synchronization is opportunistic, not a low-latency event bus. Never sync personal fixtures to a public database.

**Research:** [S15](../docs/SOURCE_INDEX.md#s15).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-017's spec now claims `implemented`. The ledger, file profile, and manual document are proven by package and Mac hosted tests. Nothing here is a live CloudKit sync or a physical-device result.

**Document format.** `native-lab-sync-ledger`, `schemaVersion` 1, with the account, scope, share, and envelopes recorded in [DATA_CONTRACTS](../docs/DATA_CONTRACTS.md#durable-sync-ledger). There is no public-database scope.

**Changed:**

- `Packages/LabFeatures`:
  - The `DurableSyncLedger` product and target (new), depending on LabDomain only. It holds `AccountID`, `DeviceID`, `ShareID`, `RecordID`, `MutationID`, `VersionVector`, `MutationEnvelope`, `ConflictRecord`, `LedgerDecision`, `RecordState`, `WriteAheadLog`, `SyncLedger`, `FileSyncProfile`, `DisabledSyncProfile`, `LedgerDocument`, `ServiceBackend`, `CloudKitSurface`, and `SyncFixtures`. CloudKit is not imported.
  - `DurableSyncLedgerTests` (new): `ConflictAndCausalTests`, `TombstoneReinstallTests`, `AccountAndProfileTests`, `LedgerOperationTests`.
  - `LabCatalogTests` now expect seven implemented experiments.
- `Apps/Shared/DurableSync/` (new): `DurableSyncExperiment`, `DurableSyncSession`, and the shared views, including the catalog launch.
- `Apps/Mac/Window/DurableSyncColumns.swift` (new).
- Hooks in shared host files, one case each:
  - `MainWindowState` has the destination and the per-window session.
  - `MainWindow` has the columns and the search prompt.
  - `SidebarView` has the row.
  - `LabCommands` has View › Durable Sync Ledger (⌘9).
  - `ExperimentDetailView` has the Open Durable Sync Ledger button.
- `project.yml` and the regenerated project, byte-identical over two runs: LabMac, LabPhone, and LabPhoneSurfaces link `DurableSyncLedger`. No new entitlement. CoreLocal still does not link CloudKit.
- `Tests/LabMacTests`: `DurableSyncHostTests` (new).
- `Fixtures/LAB-017/` (new): a public-scope document and a newer-schema document, with a README.
- `docs/DATA_CONTRACTS.md`, `docs/SOURCE_INDEX.md` (S15 installed-SDK note), `docs/VERIFICATION_BOUNDARIES.md` (CloudKit sync engine table).
- `experiments/LAB-017-durable-sync-ledger.md`: `state: implemented`, the implemented split, and implementation notes. The catalog JSON was regenerated.
- This record, and rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** The installed iOS 27.0 SDK's CloudKit interface was read for `CKSyncEngine`, `Configuration.init(database:stateSerialization:delegate:)`, `fetchChanges`, `sendChanges`, `automaticallySync`, `Event.accountChange`, `CKDatabase.Scope`, and `CKAccountStatus.temporarilyUnavailable`. Findings are in the spec's implementation notes and the verification ledger. This module does not call them.
2. **Write-ahead ledger.** Each device appends `MutationEnvelope` lines before materializing through `OperationService`. A crash between append and commit replays once (`aCrashBetweenTheLogAndTheCommitReplaysOnce`).
3. **Optional profile.** `FileSyncProfile` is a directory of one JSON file per mutation under `private/<account>/` or `shared/<share>/`. Membership is explicit. `DisabledSyncProfile` refuses before it reads or writes.
4. **Conflicts.** Concurrent edits stay inspectable until a person chooses. Choosing writes a new envelope whose version vector happened after both.
5. **Account and iCloud off.** Private partitions never cross accounts. A private document from another account is refused. iCloud off leaves export and import.
6. **Tests.** Domain operation, cancellation (`cancellingTheCommitLeavesTheLedgerUnchanged`), invalid input (empty title, overlong note, hostile fixtures), unavailable path (`disabledICloudDoesNotTouchTheProfile`), unauthorized deletion, and model-tool refusal.

**Bugs found and fixed while finishing the branch:**

- `DurableSyncViews` used `RegisteredExperiment` without importing LabCatalog; LabMac failed to compile until the import was added.
- `DurableSyncSession.title` was main-actor-isolated, so `SidebarDestination.title` could not read it. Labels moved to a nonisolated `DurableSyncExperiment` enum, matching Access as a Superpower.
- Typed-throws catches of `OperationError` and `ValidationError` warned that the `as` test is always true; they now catch the typed error directly.

**Not run:**

- A physical device.
- A live CloudKit container, account change, or `CKSyncEngine` session.
- iPad.
- VoiceOver, Voice Control, and Full Keyboard Access passes.
- A 26-SDK compile.

**Next:** [LAB-017-B](LAB-017-B.md) qualifies the ledger on its declared live path.
