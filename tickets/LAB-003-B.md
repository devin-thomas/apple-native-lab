---
id: "LAB-003-B"
title: "Qualify and document Shortcut Workbench"
status: "done"
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
- [x] Raw secret values never enter recipe exports.
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

**State: LAB-003 stays `implemented`; LAB-003-B is `done`.** Qualification first reproduced two defects in the shipped implementation, recorded as failed at `addbf39-dirty`: a fresh unbound recipe committed its import, then refused its transform; and a synthetic secret under an ordinary `prompt` field survived recipe export. Both were repaired on this branch and every acceptance criterion now passes on the fixture path, in package tests and on the Mac and iPhone simulator hosts. No live Shortcuts run occurred; the system and manual gates below remain not-run and do not block this qualification's criteria.

**Repair: the export rule.** A recipe export follows CORE-006's literal-only rule for `DiagnosticEvent` names: text leaves only when the lab wrote it. The export writes the format, the recipe's ID, each step's order and kind, and the source item IDs. It writes a title, a step's detail, or a model-step field name or value only when that string is exactly text the lab ships in `WorkbenchRecipeCatalog.bundledRecipes` (`LabAuthoredText`, built from string literals). Everything typed is withheld whatever its field is called: a typed value is written as `[withheld]`, and a model-step field whose name was typed is counted (`withheldFieldCount`), never named. `RecipeExportWithholding` reports what was withheld using only positions, counts and lab-written names, so the app's export message and the Export Recipe dialog say what was left out without repeating it. The filename falls back to "Lab recipe". `write(to:)` writes exactly the previewed bytes, without overwriting, as `DiagnosticExportPreview` does. The Inspect Model Step intent's result goes to Shortcuts, so it follows the same rule (`ModelStepExportView`); the in-app inspection still shows typed values and masks secret-shaped names. No field-name list decides secrecy; `SecretRedaction` is now only that in-app display mask. The export `formatVersion` is 2. There was no general-purpose redaction API in LabDomain or LabStaging to call, so the rule and the preview-equals-file contract were reused rather than a new mechanism.

**Repair: the runner.** `runRecipe` plans the whole run before it stages or commits anything (`planRun`): the import's collection, title and note; each query; the transform's source and resulting note; and step order. A recipe that cannot complete is refused there with nothing staged, committed or rebound. A run commits at most one operation. A recipe that imports transforms the item it imports, so every transform suffix rides on the import's single `createItem` under the run's request ID, and the new item is bound as the recipe's source (replacing any earlier binding) immediately after that commit. A recipe without an import transforms its first bound source with one `updateItem`. A refused commit discards the staged draft. Cancellation before the commit commits nothing; after it, the run finishes its read and export steps.

**Evidence.** Nine records in [evidence/LAB-003](../evidence/LAB-003/). The repair adds three, all passed on the fixture path at `ed4a1e1`: [package repair](../evidence/LAB-003/package-repair.json), [Mac hosted fresh recipe](../evidence/LAB-003/mac-host-fresh-recipe.json) (Mac Studio, macOS 27.0 (26A425)) and [iPhone simulator fresh recipe](../evidence/LAB-003/iphone-simulator-fresh-recipe.json) (iPhone 18 Pro simulator, iOS 27.0 (24A434)). Both hosts produced the same export hashes: fresh walkthrough `74f06341fc92ffd766d43917964a8574858580cdc94c2435938b36dfc4a56114`, typed-sentinel recipe `2b841aef314d230052506c45f1d972f97beaf84b5e71b9bcc601b572dd24c9c3`. The hosted records report `ed4a1e1-dirty` only because research's mirror lists its untracked `build` symlink; the mirrored sources were that commit. The earlier six records stay as they were: [fresh recipe](../evidence/LAB-003/fresh-recipe-failure.json) and [secret export](../evidence/LAB-003/secret-export-limit.json) remain the failed record of the defects at `addbf39-dirty`, superseded by the repair records. Under export format 2 the bound recipe's hash is now `dc89d3cab6b4de79527d49c1988a0de3558a921c7f3b05d7bedab04b5fd04ed3` on both hosts (was `b56d8deb…` in format 1).

**Acceptance.**

- [x] Rename survival: package `aRecipeSurvivesRenamingItsSourceItem`, `resolveIntentFindsAnItemAfterRename`, and the Mac/iPhone `boundRecipeRunsAfterRenameAndResetPreservesUserImport`, rerun at `ed4a1e1`. A saved system shortcut remains not-run.
- [x] Cancellation leaves no half import: explicit draft withdrawal, a cancelled task, a pre-cancelled fresh run (`cancelledFreshRunCommitsNothing`) and both hosted runs remove staging and commit nothing. A run now commits at most once, so no run stops between two commits.
- [x] Raw secrets never enter exports: `exportWithholdsTypedTextWhateverItsFieldIsCalled` places an invented sentinel in 22 positions (values under six secret-shaped names, under `prompt`, `tone`, new and renamed names such as `x`, `prompt_v2`, `Prompt`, `p r o m p t`, `notes.extra`; as a field name; nested in JSON; embedded in a lab-written prompt; in a config blob; in a title, a query and a transform note). It is absent from every export, filename, withholding summary and Inspect Model Step result. `exportIntentHelperReturnsWithheldBytes` checks the actual Export Recipe intent; both hosts save the typed recipe with `write(to:)` and find no sentinel in the file.
- [x] Provenance and limitations: nine records with measured toolchains, hosts, source or export hashes, and limits.
- [x] Walkthrough distinguishes fixture/backend calls from Shortcuts, Storage, Siri and a model, and now describes the fresh run and the export rule.
- [x] Public-safe material: original neutral samples, an invented sentinel, and metadata-only records; no screenshot, recording, real credential, personal shortcut or user store is retained.

The fresh four-step interaction also passes: `freshFourStepRunBindsItsImportAndCompletesInOneCommit` (four steps, one appUI `createItem` carrying the transform, ID bound in catalog and export, same-request retry replays the first receipt) and the hosted `freshRecipeCompletesInOneCommitAndExportWithholdsTypedText` on both hosts.

**Failure cases.** `unrunnableRecipeIsRefusedBeforeAnythingIsStagedOrCommitted` covers transform without a source, transform before import, two imports, no collection, an unknown collection, an oversized transformed note, an invalid query and a missing bound item: each throws with no commit, no item change, no draft, and an unchanged catalog. `refusedImportCommitLeavesNoDraftAndKeepsThePreviousBinding` has the operation service refuse a reused request ID at the commit itself. Duplicate import returns the first receipt; changing its payload is refused. Stale updates return a conflict, and a denied actor writes nothing. Reset Demo preserves imported user data and the process catalog. A bound recipe's transform still uses a fresh request ID, so repeating a completed bound run appends its suffix again.

**Changed.** Sources: `RecipeExport.swift` (export rule, `RecipeExportWithholding`, `LabAuthoredText`, `ModelStepExportView`, `write(to:)`), `WorkbenchActions.swift` (`planRun`, single-commit `runRecipe`, staged-commit helper), `WorkbenchIntents.swift` (export dialog, model-step result), `RecipeDefinition.swift` (format 2), and copy in `ManualRecipe.swift`, `TypedActionContract.swift`, `SecretRedaction.swift` and `ShortcutWorkbench.swift`. Host: `ShortcutWorkbenchModel.export` reports what was withheld. Tests: the two characterization tests now assert the repaired behavior, with 8 refusal cases, 22 export placements, a refused-commit case, a cancelled fresh run, and a bundled-recipe check (25 package tests, from 21); one new hosted check on each of Mac and iPhone. Docs: experiment notes, walkthrough, fixture README, VERIFICATION_BOUNDARIES and BUILD_STATUS. No host hook, target, entitlement, project, catalog metadata or shared package changed.

**Commands and results.** Through `labr`: narrow `swift test --package-path Packages/LabFeatures --filter ShortcutWorkbench` passed, 25 tests in 3 suites (at `28b8202`, and again in the gate). Focused hosted runs (`-only-testing` the two Shortcut Workbench host suites, at `71900d3` with uncommitted docs) passed on Mac (3 tests) and in a new iPhone 18 Pro simulator (2 tests), created and deleted by the run; the first focused attempt failed to compile a host test on an internal initializer, fixed in `71900d3`. Full `LAB_SIMULATOR_PREFIX="NL LAB-003-B-fix" script/test.sh` passed on the first attempt: validators 8/8, 93 self-tests, LabSupport 97, LabDomain 187, LabStore 61, LabStaging 40, LabDemo 119, LabFeatures (ShortcutWorkbench 25; Share Ingress's two known issues), Mac hosted 186 passed, 3 skipped, 1 expected failure, 0 failed; iPhone 11 passed; Watch and TV stages; release manifests for CoreLocal, SystemSurfaces and Companions; CloudOptional and FrontierOptional skipped. Attachments were exported from the gate's result bundles with `xcresulttool`. Final repository validation is recorded in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Not run.** Live Mac/iPhone/iPad Shortcuts, Siri, system authentication prompts, Storage, cross-device identity, model transcript, physical mobile devices, iPad simulator, OS 26 compile, UI controls/audit, VoiceOver, Voice Control, Full Keyboard Access, large text and reduced motion. Static accessibility findings remain open, including no Cancel control and result feedback on the overview rather than the action page.

**Lead follow-up.** Owner decision: person-authored recipes now export as structure and IDs only; any opt-in to include typed text would need its own reviewed consent path. Run live Shortcuts (including the Export Recipe and Run Import–Export Recipe intents) and manual accessibility on isolated fixtures. Physical mobile runs require the owner. A bound run still saves its bound copy over the walkthrough in the session catalog, so a later unbound run in that session runs the bound copy.

**Next dependency-ready ticket:** LAB-032-B; LAB-005-A still waits on it.
