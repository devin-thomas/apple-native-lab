---
id: "CORE-003"
title: "Build local persistence and original fixture namespaces"
status: "done"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-002"]
---

# CORE-003 — Build local persistence and original fixture namespaces

## Goal

Provide useful offline state while preventing demo resets and migrations from losing imported user data.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Packages/LabStore, Fixtures, migration tests.

## Implementation steps

1. Select and record a transactional store implementation
2. Implement schema versioning and a deterministic fixture seed
3. Separate demo namespace from user-imported namespace
4. Implement reset, migration, conflict, and recovery tests

## Acceptance criteria

- [x] An interrupted transaction leaves either the old or complete new state.
- [x] Reset Demo preserves a deliberately imported user record.
- [x] A released schema migration preserves stable IDs and unknown supported metadata.
- [x] A corrupt fixture import does not prevent the next valid one.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

**Changed:**

- New package `Packages/LabStore`, with library `LabStore` and tests `LabStoreTests`.
- `Packages/LabDomain`: namespaces and Reset Demo, with new tests in `NamespaceTests.swift`.
- `Fixtures/demo/seed.json` and `Fixtures/README.md`.
- `docs/DATA_CONTRACTS.md`: a new section, "Local store and namespaces".
- A draft `docs/adr/ADR-012.md`.
- Evidence rows in `docs/BUILD_STATUS.md` and this ticket.

No app target, project, config, script, or LabSupport file changed, and no host uses the store yet.

**Store choice: SQLite, through the system `SQLite3` library** (ADR-012, proposed).

- `BEGIN IMMEDIATE` takes the write lock before the receipt check and the revision checks. The checks and the writes therefore hold one lock, across connections and processes, as a future App Group store needs.
- Migrations are ordered SQL steps under `PRAGMA user_version`, each in its own transaction.
- The library is available on iOS, macOS, watchOS, and tvOS, and `swift test` needs no host app.
- Core Data and SwiftData detect conflicts optimistically, when they save. The checks would read before the lock, so they would need extra machinery to meet the same contract.

**What exists:**

- `SQLiteOperationStore`, an actor on its own serial dispatch queue. It uses write-ahead logging with `synchronous = FULL` and a 5-second busy timeout, and refuses a newer or foreign file without changing it.
- Schema version 1 has entities, receipts, and an `extras` JSON column the store never rewrites. Version 2 adds namespaces.
- Triggers keep every entity in its namespace, put each item in its collection's namespace, never delete a user row, and never update or delete a receipt.
- `DemoFixture` loads the strict seed format, checking the whole file first, and computes a SHA-256 of the file for evidence records.
- In LabDomain: `DataNamespace`, `DemoSeed`, and `DomainOperation.resetDemo(seed:)`. Reset Demo is destructive, so only the app UI and App Intents can commit it. One commit restores changed samples at their next revision and removes leftover demo entities. Creating an item in a demo collection is refused.

**Acceptance evidence.** `swift test --package-path Packages/LabStore` runs 37 tests (70 cases with arguments) in 7 suites, all passing, with 0 warnings on a clean build. `swift test --package-path Packages/LabDomain` runs 65 tests: CORE-002's 49 plus 16 new.

- **Interrupted transaction** (`InterruptedTransactionTests`):
  - The Reset Demo commit under test rewrites 3 samples and removes 1 in one transaction.
  - `everyInterruptionBeforeCommitLeavesTheOldStateAndTheRetryCompletesIt` stops the commit at each of its 8 fault points before `COMMIT`, on a fresh store each time. Each time, every row of every table matches the old state, including through a new connection, and no receipt exists. The same request then commits the complete new state.
  - `anInterruptionAfterCommitLeavesTheCompleteNewStateAndTheRetryReplays` stops after `COMMIT`. The file holds the complete new state, and the retry returns the recorded receipt without committing again.
  - `aCrashMidTransactionRecoversTheOldStateFromTheFilesOnDisk` copies the database and its log in the middle of a 151-row commit. It first checks that uncommitted pages had reached the log (the WAL grew before `COMMIT`). Opening the copy gives exactly the old state, and a copy taken after `COMMIT` gives exactly the new state.
- **Reset Demo keeps an imported record:** `resetDemoPreservesADeliberatelyImportedUserRecord` runs against the SQLite store and the repository seed.
  - A record imported through the share extension, then edited, with import metadata in `extras`, keeps every column of its row across a reset, and after reopening the file.
  - Edited and archived samples return to the seed.
  - A share-extension reset is refused.
  - `theFileItselfRefusesToDeleteOrReassignUserRows` sends 8 raw SQL attempts past the store's code; the triggers refuse all 8.
  - LabDomain's `resetDemoNeverTouchesUserData` and `StoreInvariantTests` (both stores) cover the same rule.
- **Migration** (`MigrationTests`):
  - A version 1 file built from frozen SQL migrates to version 2. Every column of every row is unchanged, with `namespace = 'user'` added. IDs, revisions, Unicode text, and nested or `null` `extras` survive, and receipt bodies stay byte-identical, including an unknown field.
  - `extras` also survives a later update and a Reset Demo.
  - A migrated file has exactly the schema of a new file.
  - An interrupted migration leaves version 1 intact.
  - Newer and foreign files are refused byte-for-byte unchanged.
- **Corrupt fixture** (`FixtureImportTests`):
  - Each of 18 corruptions is rejected with a specific error before anything is written, and the valid seed then imports: empty, truncated, non-UTF-8, array, oversized, wrong format or version, missing, mistyped, or unknown fields, a blank title, a control character, a malformed UUID, a duplicate ID, a dangling collection, seed version 0, and no collections.
  - A well-formed fixture that names a user entity's ID is refused and writes nothing.
  - An import stopped in the middle of its commit writes nothing, and the next import succeeds.
- **Store contract, both stores** (`StoreContractTests`):
  - The duplicate-request tests: same request twice; replay after later changes; 48 concurrent duplicates; 24 across three connections; a reused ID with another payload or adapter.
  - The precondition tests: stale revision; a writer in another process between read and commit; a creation pinned against a concurrent archive; 12 concurrent writers over three connections.
  - The failed-commit test: SQLite fails inside its transaction, after every write.
  - `bothStoresProduceIdenticalReceiptsAndState` runs a 9-step script and finds equal receipts and state in both stores.
- **Across processes** (`CrossProcessTests`, macOS): while a commit is between its checks and its writes, a separate `/usr/bin/sqlite3` process fails with "database is locked". Afterwards it writes, and a stale commit from this store becomes a conflict.

**Checks that the tests have teeth:** copies of the package, each with one guarantee removed.

- A deferred `BEGIN` fails the cross-process lock test.
- No transaction fails 8 tests, including the interruption, crash-recovery, and failed-commit tests.
- An upsert that clears `extras` fails the metadata migration test.
- A store allowed to delete user rows fails 4 tests.

**Repeat runs:** 0 failures in 30 full LabStore runs, 30 full LabDomain runs, and 100 runs of the concurrency, cross-process, and interruption tests.

**LabDomain API changes:**

- `DomainOperation.target` is now `EntityReference?`, `nil` for Reset Demo. This breaks callers, but nothing outside the package used it.
- New enum cases: `DomainOperation.resetDemo`, `OperationKind.resetDemo`, and `RuleViolation.demoCollection`.
- New protocol requirement: `OperationStore.collections()`.
- `AuthorizedCommit.removals` and `ActionReceipt.removed` are new. `removed` is encoded only when it is not empty, so earlier receipts keep their exact JSON.
- `LabCollection` and `LabItem` gain `namespace`. Their initializers take it as a defaulted last argument, and a value without it decodes as `user`.
- `InMemoryOperationStore.apply` now throws `NamespaceViolation`.
- New types: `DataNamespace`, `DemoSeed`, `DemoSeedError`, and `NamespaceViolation`.

**Not run:**

- `script/test.sh` does not include LabStore yet; the script is not mine to edit. It passes unchanged with LabDomain's 65 tests.
- No host links LabStore or bundles the seed.
- There is no App Group container, file protection class, or suspended-extension lock test. Those need the build configuration (CORE-008) and a paid team (CORE-006 and later).
- The cross-process tests use the `sqlite3` tool as the other process, not a second LabStore process.
- Durability of the latest commits against sudden power loss is not claimed, because `fullfsync` is off.

**Specification notes:**

- ARCHITECTURE separates demo and user data "by namespace and storage location". This implementation uses one file and a namespace column instead, because SQLite in WAL mode does not commit two files atomically. The seed stays separate, as read-only data in `Fixtures/`. ADR-012 records this and needs review.
- A person cannot add items to a demo collection, which guarantees that Reset Demo never removes something a person created. Edits to samples are reverted by design.
- Schema "version 1" is the pre-namespace format, defined in this ticket as the first released step. No build has shipped it; it exists so the migration path is exercised from the start.

**Requests for other owners:**

Integration: add these lines to `script/test.sh`, after the LabDomain step. Also review ADR-012, and add it to `ADR.md` if accepted. (Done at integration.)

```bash
step "LabStore package tests"
swift test --package-path Packages/LabStore --quiet
```

When a host adopts the store (CORE-005): add the `LabStore` package to `project.yml`, and bundle `Fixtures/demo/seed.json` as a resource.

**Next dependency-ready ticket:** CORE-004, which depends only on CORE-001. CORE-006 is now dependency-ready too, since CORE-002 and CORE-003 are done.
