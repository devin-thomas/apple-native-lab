---
id: "CORE-009"
title: "Implement replayable demonstrations and evidence export"
status: "done"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-003", "CORE-006", "CORE-007"]
---

# CORE-009 — Implement replayable demonstrations and evidence export

## Goal

Turn each successful experiment into an inspectable demonstration without inventing test results.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Demo runner, evidence exporter, original showcase fixtures.

## Implementation steps

1. Add fixture reset and scripted local action sequences
2. Record receipts and measured intervals using declared timebases
3. Build a selected-artifact export preview with rights/privacy review
4. Include hashes, toolchain/adapter metadata, failures, and untested areas

## Acceptance criteria

- [x] Replaying a deterministic fixture produces the same domain result. (`ReplayTests`: two SQLite replays on different clocks, and a SQLite and an in-memory replay, have equal receipts and final state; their JSON differs only in the named fields. Fixture path.)
- [x] An unrun step cannot acquire a passing badge. (`UnrunStepTests`: skipped, cancelled, and blocked steps are `not-run` or `blocked`, with no interval, receipt, or read; their evidence record never passes; the export summary leads with the worst result.)
- [x] An export does not include adjacent directories or hidden source media. (`ConfinementTests`: traversal names, links, hidden files and flags, folders, hard links, media types, and binaries disguised as text are refused, and the written folder holds only the previewed files.)
- [x] Every published performance claim links to a measured run. (`TimingTests`: a claim exists only for a passing step or run on a real-time clock, and an export refuses a claim whose run it does not contain.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

**Changed:**

- New package `Packages/LabDemo`, with library `LabDemo` and tests `LabDemoTests` (60 tests in 8 suites).
- New `Fixtures/showcase/`: a README and the `atlas-basics` script and seed.
- `docs/TEST_STRATEGY.md`: a new section, "Replayable demonstrations".
- `docs/EVIDENCE_TEMPLATE.md`: a new section, "Exported evidence".
- Evidence rows in `docs/BUILD_STATUS.md` and this record.

No app target, project, config, script, workflow, or existing package changed, and no host uses the new code yet.

**Why a new package:** the runner needs LabDomain (operations, grants), LabStore (a fresh SQLite store and the strict seed format), and LabSupport (the evidence vocabulary and `BuildProvenance`). LabSupport must not depend on LabDomain, and evidence tooling does not belong in the domain or the store, so the one package that needs all three holds both the runner and the exporter.

**Runner** (`DemoScript`, `DemoRunner`, `DemoRun`):

- A script is a seed and a declared list of steps, each with a name. `approve` names a later step. `perform` submits one operation under its own request ID: Reset Demo with the script's seed, any other domain operation with its expected revision, or the undo recorded in an earlier step's receipt. `find` reads through the service and lists the item IDs it expects, in order.
- Scripts load strictly: confined, visible, singly linked files; strict JSON; no unknown field at any level. The first change must be Reset Demo with the script's own seed.
- A script cannot name an actor, a permission, or a grant. The runner acts as its adapter (the app UI by default) holding that adapter's ceiling (ADR-011). It composes `OperationService` with `GrantAuthorizationPolicy`, and its only grants are the ones `approve` steps ask the ledger for, each for exactly one later step (ADR-013).
- Every run opens a new store, and refuses one that already holds a collection or an item.
- Receipt IDs derive from the script's input hashes, so a replay repeats every receipt exactly. `DemoRun.fieldsExcludedFromReplay` names what may differ: `runID`, `startedAt`, `environment`, and the three interval fields. `replayFingerprint` is the SHA-256 of the rest, and `ReplayComparison` names any difference.
- Step intervals come from an injected `IntervalClock`. The run records its `Timebase` and unit: `swift-continuous-clock`, `swift-suspending-clock`, or `manual-test-clock`, which measures nothing.
- A step record's result is a `RunOutcome`. After a step that does not pass, the rest are `not-run` (skipped). After a cancellation, the steps that had not started are `not-run` (cancelled). A store that cannot open makes every step `blocked`. Only a step that ran can pass, and it always has an interval.
- `DemoRun` and its step records have no public initializer and no decoder, so a run in memory is one that ran in this process. `DemoRun.evidenceRecord(provenance:)` returns a fixture-path `EvidenceRecord` carrying the worst result, the input hashes, the steps, and every limitation.

**Exporter** (`EvidenceExporter`, `EvidenceExportPreview`):

- **Selection.** The caller selects runs, evidence records, and single text files, each under an export name it chooses.
- **Preview.** `preview(_:)` computes every byte first. `write(into:folderName:)` writes those files into a temporary folder with exclusive, no-follow creates, checks it holds exactly the previewed files and bytes, then renames it into place without replacing anything.
- **Rights and privacy review.** Each artifact declares a `DataTier`. `public-fixture` is approved. `user-private` and `unclassified` need a `TierOverride` naming the export path, the tier, and a reason, which the manifest and summary record. `sensitive` is always refused.
- **Confinement.** File sources pass `StagedPath` (LabDomain's import path policy) and a component walk that refuses links, hidden names or flags, and anything but one ordinary file. The file is then opened with `O_NOFOLLOW`, and its descriptor must be singly linked and still below the root. Only JSON, Markdown, text, and CSV are allowed, and the bytes must be UTF-8. Media is refused, because its embedded metadata is not stripped. Export names must be visible, must not collide under case or normalization, and must not reuse `summary.md` or `manifest.json`.
- **Contents.** `manifest.json` records `BuildProvenance`, each run's adapter, store, timebase, input hashes, and fingerprint, every file's SHA-256 and size, the review, every failure and unrun step, the untested areas, and the performance claims. `summary.md` starts with the worst result.
- **Performance.** A `PerformanceClaim` can be made only from a passing step or run on a real-time timebase, and the export refuses a claim whose run is not an approved artifact in it.

**Showcase:** `Fixtures/showcase/atlas-basics` resets the demo (2 collections, 5 items), lists one collection, finds, renames, finds again, archives, confirms the archive hides the item, undoes it from the recorded receipt, and finds it again. Reset Demo is the only way to create anything in the demo namespace (ADR-012), so it is the create step.

**Acceptance evidence** (fixture path, macOS; see BUILD_STATUS):

- **Replay:** `replayingTheShowcaseReproducesReceiptsAndFinalState`, `theSQLiteAndInMemoryStoresReplayToTheSameResult`, `onlyTheNamedFieldsDifferBetweenReplays`, `receiptIDsAreDerivedFromTheInputsNotRandom`, and `aChangedSeedChangesTheDomainResult`. The showcase fingerprint was `79753d83…9cf9633f` in every run, across processes.
- **Unrun steps:** `stepsAfterAFailureAreSkippedAndNotRun`, `cancellingBeforeTheRunMarksEveryStepCancelled`, `cancellingMidRunLeavesTheRemainingStepsCancelled`, `aStoreThatCannotOpenBlocksEveryStep`, `aStoreHoldingAPersonsDataIsRefused`, `theEvidenceRecordOfAnUnfinishedRunNeverPasses`, and `theSummaryStartsWithTheWorstResult`. `checkStepInvariants`, applied to the runs these tests produce, checks that a passed step ran and has an interval, and that a step that never started is never passed.
- **Grants:** `aDestructiveStepWithoutItsApprovalFailsAtTheCommit`, `withoutTheResetApprovalNothingIsCommitted`, and `anApprovalCannotWidenTheAdapter`.
- **Confinement:** `ConfinementTests` (14 tests) and `ScriptLoadingTests` (11). `aLinkSwappedInAfterTheCheckIsRefusedWhenOpened` covers a swap between the check and the open. `onlyTheAllowlistReachesTheDestination` confirms that no private sentinel text or source path reaches any written file.
- **Performance:** `aClaimNeedsARealTimeClock`, `aClaimNeedsAStepOrRunThatPassed`, `anExportRefusesAClaimWhoseRunIsNotInIt`, and `withoutClaimsTheSummaryPublishesNoNumber`.
- **End to end:** `theShowcaseExportsEndToEnd` runs two SQLite replays with the continuous clock, exports them with their record, inputs, and two claims, writes the export, and reads the record back.
- **Mutation checks:** 14 of 14 caught (BUILD_STATUS).

**Evidence location:** the showcase export generated at 79704a6 stayed outside the repository, and `evidence/` still holds no record. `script/validate/tests/test_evidence.py` expects that folder to be empty, so storing the export's record there needs that test changed first.

**Not run:**

- Any host, intent, or extension using the runner or exporter. No such caller exists yet.
- Physical devices.
- LabDemo tests in a simulator. The package compiled for the iOS, watchOS, and tvOS simulators, but its tests ran only on macOS.
- The CI step for LabDemo, which is not in `script/test.sh` or the workflow yet.

**Specification notes:**

- "Create" in the demo namespace is Reset Demo, because items cannot be added to demo collections (ADR-012).
- `RunResult` has no `skipped` or `cancelled`. A step record adds a `disposition` (`ran`, `skipped`, `cancelled`, `blocked`), and its result stays in the CORE-007 vocabulary.
- LabStaging's link-safe file helpers are internal, so LabDemo reuses LabDomain's public path policy (`StagedPath`, `StagedPathSet`, `StrictJSON`, `StrictUTF8`, `ContentDigest`) and has its own descriptor-level checks.
