---
id: "LAB-003-B"
title: "Qualify and document Shortcut Workbench"
status: "blocked"
milestone: "M2"
kind: "qualification"
depends_on: ["LAB-003-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-003-B — Qualify and document Shortcut Workbench

## Goal

Prove Shortcut Workbench on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-003-shortcut-workbench.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** shortcut-workbench tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: A recipe survives renaming its source item; Cancellation does not leave half an import; Raw secret values never enter recipe exports
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [x] A recipe survives renaming its source item.
- [x] Cancellation does not leave half an import.
- [ ] Raw secret values never enter recipe exports.
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [x] The walkthrough never claims a simulation is the live integration.
- [x] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone, iPad, Mac.

**Unavailable path:** Manual recipe instructions and app action browser; no secret storage inside Shortcuts.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-003 stays `implemented`; LAB-003-B is `blocked`.** Qualification reproduced two blockers in the shipped implementation: a fresh unbound recipe commits its import, then refuses transform; and a synthetic secret under an ordinary `prompt` field survives recipe export. No live Shortcuts run occurred. Successful bound-fixture runs do not close these gates.

**Evidence.** Six records in [evidence/LAB-003](../evidence/LAB-003/): package contracts (passed), fresh recipe (failed), unrestricted secret export (failed), Mac hosted bound recipe (passed, fixture), iPhone simulator-hosted bound recipe (passed, fixture), and system/manual gates (not-run). Build provenance is `addbf39-dirty`, Xcode 27.0 (27A266a), Swift 6.4. Mac Studio: macOS 27.0 (26A425); iPhone 18 Pro simulator: iOS 27.0 (24A434). The neutral bound recipe hash is `b56d8deb688e0634b16a5bed6ad2d23f75b99ea16a069b3da94fd1d9515bf39c` on both hosts. Package records hash the actual fixture sources. Host records were extracted from passing xcresult attachments and annotated with their measured host environments; no device identifiers were retained.

**Acceptance.**

- [x] Rename survival: package `aRecipeSurvivesRenamingItsSourceItem`, `resolveIntentFindsAnItemAfterRename`, and the Mac/iPhone `boundRecipeRunsAfterRenameAndResetPreservesUserImport`. Stable ID retained; saved system shortcut remains not-run.
- [x] Cancellation before import commit: explicit draft withdrawal, cancelled task, and both hosted runs remove staging and refuse a cancelled commit. This does not claim whole-recipe rollback after a committed step.
- [ ] Raw secrets never enter exports: `redactionCoversSecretShapedKeysButNotArbitraryText` proves the unrestricted claim false. Six secret-shaped keys and `ExportRecipeIntent.run` redact correctly; ordinary text does not.
- [x] Provenance and limitations: six records; actual hashes and bundle provenance.
- [x] Walkthrough distinguishes fixture/backend calls from Shortcuts, Storage, Siri and a model.
- [x] Public-safe material: original neutral samples, synthetic sentinels, and metadata-only records reviewed; no screenshot, recording, real credential, personal shortcut or user store is retained.

**Failure cases.** Duplicate import returns the first receipt; changing its payload is refused. Stale updates return a conflict, and a denied actor writes nothing. Reset Demo preserves imported user data and the process catalog. Full recipe retries are not idempotent: transforms use fresh request IDs. The fresh run’s exact error is `This recipe has no source item to transform.` Its newly imported item remains. Characterization tests pass by reproducing these failures; the interactions are recorded as failed.

**Changed.** Seven package qualification tests, one hosted check on each of Mac and iPhone, six evidence records, original-fixture notes, a publication-safe [walkthrough](../docs/walkthroughs/LAB-003-shortcut-workbench.md), an accessibility source review, SDK/source notes and the build ledger. No app behavior, host hook, capability descriptor, target, entitlement, project or catalog metadata changed. No ADR is needed for an evidence-only correction.

**Commands and results.** Through `labr`: narrow ShortcutWorkbench tests passed (20, then final 21); SDK `grep` probe passed (`rg` was unavailable); full `LAB_SIMULATOR_PREFIX="NL LAB-003-B" script/test.sh` passed once. Mac summary: 185 passed, 3 skipped, 1 expected failure, 0 failed (parameterized executions counted separately); iPhone: 10 passed, 0 failed. The new hosted check passed on each. Watch/TV simulator stages and release manifests for CoreLocal, SystemSurfaces and Companions passed; unused profiles skipped. Share Ingress retained its two known issues. Attachment export used `xcresulttool` through `labr`. Final repository validation is recorded in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Not run.** Live Mac/iPhone/iPad Shortcuts, Siri, system authentication prompts, Storage, cross-device identity, model transcript, physical mobile devices, iPad simulator, OS 26 compile, UI controls/audit, VoiceOver, Voice Control, Full Keyboard Access, large text and reduced motion. Static accessibility findings remain open, including no Cancel control and result feedback on the overview rather than the action page.

**Lead follow-up.** Repair the fresh runner’s binding and resolve the unrestricted export-safety contract before closing qualification; then run live Shortcuts and manual accessibility on isolated fixtures. Physical mobile runs require the owner. The existing local bound fallback remains usable.

**Next dependency-ready ticket:** LAB-032-B; LAB-005-A still waits on it.
