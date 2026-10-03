---
id: "LAB-017-B"
title: "Qualify and document Durable Sync Ledger"
status: "blocked"
milestone: "M3"
kind: "qualification"
depends_on: ["LAB-017-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-017-B — Qualify and document Durable Sync Ledger

## Goal

Prove Durable Sync Ledger on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-017-durable-sync-ledger.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** durable-sync-ledger tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Conflicting edits remain inspectable; Deleting and reinstalling does not resurrect tombstoned data accidentally; Account A data never appears in account B
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [x] Conflicting edits remain inspectable.
- [x] Deleting and reinstalling does not resurrect tombstoned data accidentally.
- [x] Account A data never appears in account B.
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [x] The walkthrough never claims a simulation is the live integration.
- [x] Only approved original/public-safe material enters screenshots and exports.

These checks qualify only the file-profile/manual-document fixture paths, as detailed in the completion record. Live CloudKit qualification is blocked: LAB-017-A supplies no CloudOptional ledger adapter or host. Hosted tests also reproduce failed live-record restoration after reopening. No Apple account change, OS reinstall, or physical device run is claimed.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone, iPad, Mac; companion state distribution separately.

**Unavailable path:** Local store plus manual document exchange.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-017 stays `implemented`; LAB-017-B is `blocked` on live qualification.** LAB-017-A implements a file profile and manual exchange, with no CKSyncEngine adapter or CloudOptional ledger host. A synthetic private partition is not an Apple account, and wiping a ledger directory while keeping its file profile is not an OS uninstall/reinstall. No physical device, live account, container, network sync, or companion distribution was attempted.

**Acceptance (fixture paths only).**

- [x] Conflicts remain inspectable: `ConflictAndCausalTests` keeps both offline notes and the explanation until a person chooses. `DurableSyncQualificationTests.aStaleChoiceCannotReplaceTheResolvedRecord` refuses a repeated choice without changing the document, then both synthetic devices converge.
- [x] Tombstones prevent accidental resurrection: the existing tombstone tests and `wipingTheSameDeviceDirectoryRetainsTheRemoteTombstone` remove/recreate the same synthetic device directory, pull the retained tombstone, import the older document twice, and remain deleted with two envelopes. No OS reinstall ran.
- [x] Account A never appears in B: `AccountAndProfileTests` proves separate private file partitions, refuses another account's document/directory, and refuses a shared-profile stranger. No Apple account switch ran.
- [x] Evidence names measured toolchain, input hashes, adapter paths, and limitations; see `evidence/LAB-017/`.
- [x] The publication-safe walkthrough opens with the local replay boundary and distinguishes package reinstall simulation, hosted-session calls, and untested file-dialog gestures.
- [x] Only approved original/public-safe material: evidence contains synthetic fixture/source hashes and observations. No screenshots, recordings, raw stores, exported document contents, accounts, or real user material are published.

**Hosted evidence and open defect:** the Mac filter ran 5 tests: 4 passed, 1 expected failure. Its independent Mac-only repeat gave the same counts. The iPhone 18 Pro simulator (iOS 27.0, 24A434) ran 2 tests: 1 passed, 1 expected failure; the run created/deleted only its own simulator. `cleanReplayDeletionManualExchangeAndConfinedReset` passed on both hosts. `reopeningRetainsTheLogButDoesNotRebuildTheLiveView` retained export bytes but failed the live-state expectation: opening a new session shows the saved live record as absent, because the applied markers survive while the host creates a fresh in-memory operation store. No fix was made in this qualification ticket. Both hosted evidence records use `failed` for restoration even though the test harness reports Passed with the declared known issue. Reopening also occurs when toggling the profile, so this is a local durability limitation, not just a CloudKit gate.

**Package cases:** 17 tests in 5 suites passed: conflicts/causality, tombstones, account/private/shared boundaries, disabled profile (zero pull/push calls), model-tool and ungranted deletion denial, invalid inputs/public scope/newer schema, crash replay, duplicate import, cancelled backend commit, pre-start cancelled import with successful retry, and stale conflict choice. The first baseline filter ran 14 tests in 4 suites; the second included the three new qualification tests.

**Changed:** DurableSyncLedger package qualification tests; Mac and iPhone hosted-session qualification tests; `evidence/LAB-017/`; publication-safe walkthrough; accessibility review rows; installed-SDK verification note; experiment qualification boundaries; this ticket record and BUILD_STATUS rows. No production implementation, shared host hook, target, entitlement, dependency, project, or catalog change. Test sources are in commit `787fcfb`.

**Full gate:** `LAB_SIMULATOR_PREFIX="NL LAB-017-B" script/test.sh` ran once through `labr`, with pipefail and a saved build log, at `787fcfb-dirty`. Validators 8/8, 93 validator self-tests, every package stage, and Mac hosted tests passed. Mac summary: 199 total, 194 passed, 2 expected failures, 3 skips. The script stopped at iPhone (14 total: 12 passed, 1 expected ledger-reopen failure, 1 unexpected failure) with `RenderSurvivesPhoneTests.aRenderRecordsTheRunwayIOSGrantedAndPublishesTheMovie`: `Expectation failed: model.reports[job.id]`, even though its job was succeeded. This is the assigned LAB-032 report-publication flake; no unrelated source was patched. Watch/TV/manifest were not reached by this command. One focused retry and the remaining stages are recorded separately.

**Single retry and remaining gates:** the focused LAB-032 iPhone retry was blocked before execution by `Failed to install or launch the test runner` / `No such process`. No second retry ran and no render pass is claimed. A temporary runner copied the existing simulator functions and Watch/TV/manifest suffix from `script/test.sh`, with that focused retry before them. Watch smoke/packages passed on Apple Watch Series 12 (46mm), watchOS 27.0 (24R362). Apple TV hosted/remote-focus/packages passed on Apple TV 4K (3rd generation), tvOS 27.0 (24J360). The Source-lane release manifest passed: CoreLocal, SystemSurfaces, Companions built within policy; CloudOptional and FrontierOptional skipped (no schemes). Ticket-created simulators were removed; the temporary runner was removed and no tracked script changed. These later passes do not erase the initial gate failure. Exact command rows are in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Source/toolchain:** all builds/tests use `labr`. Research reported Xcode 27.0 (27A266a), Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS 27.0 (26A425), iOS SDK 27.0. The first SDK probe failed because Research has no `rg`; the follow-up `grep` probe confirmed CKSyncEngine availability and configuration signatures. Apple's S15 documentation was read; live app-owned state persistence and account-change handling remain unqualified.

**Review:** native text controls, conflict device labels/hints, wrapping explanations, semantic text states, and Mac navigation shortcut are present by static inspection. Manual accessibility, rendered layout, focus, and announcements remain not-run. Save/reconnect/manual exchange have no dedicated Mac menu shortcuts. `importFile` reads the whole file on the main actor before the decoder enforces its 2 MiB bound. No behavior was changed to conceal these findings.

**Not run:** physical iPhone/iPad, iPad simulator, live CloudKit/CKSyncEngine/container/account change, OS uninstall/reinstall, file-dialog gestures, companion state distribution, VoiceOver, Voice Control, Full Keyboard Access, large text/contrast/reduced motion, and a 26-SDK compile.

**Final validation:** `python3 script/validate/all.py` passed 8/8 through `labr` with 58 evidence records, including all four LAB-017 records; the catalog is current. Local `git diff --check` passed. No project or catalog regeneration was needed.

**Lead gate:** fix the host restoration/materialization defect in a separately scoped implementation before claiming durable local state across reopening. A separately scoped CloudOptional implementation and configured signed container are required before live qualification. Owner-authorized device/account runs must provide their own evidence; local fixture passes do not establish release readiness.

**Next dependency-ready ticket:** LAB-016-B (LAB-016-A and CORE-007/009/010 are done in this checkout). No second ticket was started.
