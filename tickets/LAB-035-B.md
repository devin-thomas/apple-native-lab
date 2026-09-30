---
id: "LAB-035-B"
title: "Qualify and document Access as a Superpower"
status: "done"
milestone: "M1"
kind: "qualification"
depends_on: ["LAB-035-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-035-B — Qualify and document Access as a Superpower

## Goal

Prove Access as a Superpower on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-035-access-as-a-superpower.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** access-as-a-superpower tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: No information is encoded by color alone; Keyboard and VoiceOver can finish the full task; An unsupported sonification API retains a table and summary
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] No information is encoded by color alone.
- [ ] Keyboard and VoiceOver can finish the full task.
- [ ] An unsupported sonification API retains a table and summary.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone, iPad, Mac; Watch/TV adapt primary tasks.

**Unavailable path:** Semantic list/table and standard platform controls.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

**State: LAB-035 stays `implemented`.** Four records in `evidence/LAB-035/` at fd8523e: three fixture, one simulator, none physical. No person has used an assistive technology on the experiment.

**The one run that would promote it.** A person runs the VoiceOver and Audio Graph passes in [the manual script](../docs/walkthroughs/LAB-035-manual-passes.md) on the Mac or the iPhone, finishes the task, and records it with `DeviceRunEvidence`.

**Acceptance.**

- [x] No information is encoded by color alone: `archivedAndActiveSquaresDifferWithoutColor` renders both squares with the fill hidden (one outline unbroken, the other dashed); the key names the shapes in primary text; counts are digits with "Most" and a star; `everyArchiveStateReadsCompletelyInWords`. A person's grayscale pass is `not-run`.
- [ ] Keyboard and VoiceOver can finish the full task. Keyboard: AppKit-delivered keys finish it in the hosted tests. VoiceOver: only the structure is proven, in the test bundle and across processes in the running app. Unchecked until a person finishes the task with VoiceOver.
- [x] An unsupported sonification API retains a table and summary: the hosted fallback way (60 of 60 comparisons), LAB-035-A's test across all 6 display overrides, and `theTableAndSummaryCarryTheDescriptorsNumbersInEveryPracticeState`.
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations: four records, all valid.
- [x] The walkthrough never claims a simulation is the live integration: it opens with "No person has used…", every screenshot says it is from the simulator, and the grayscale image is labeled as a conversion.
- [x] Only approved original material enters screenshots and exports: the export review approved 6 of 6 as `public-fixture` with no override; screenshots are the app's own demo content from a simulator created for the ticket and deleted afterwards.

**Cases:** denial (`withoutTheApprovalPracticeArchivesNothing`, `aPracticeArchiveWithoutTheGrantIsRefusedAndTheRestoreNeedsNone`), cancellation (`aCancelledPracticeSetUpKeepsOnlyWhatCommitted`), stale state (`aRestoreFromAStaleRevisionIsAConflictThatChangesNothing` and the stale set-up, reset, and chart cases), duplicates (`aSecondPressWhileTheRestoreRunsCommitsOnce` and the late retry), and reset beside imported data (`resetPracticeLeavesImportedAndOwnDataUntouched`).

**Changed:** `evidence/LAB-035/` (4 records), `docs/walkthroughs/LAB-035-access-as-a-superpower.md` with 4 simulator screenshots, `docs/walkthroughs/LAB-035-manual-passes.md`, an Access as a Superpower review in `docs/ACCESSIBILITY_REVIEW.md` (the LAB-035-A findings rechecked and 2 new findings), a chart-semantics ledger in `docs/VERIFICATION_BOUNDARIES.md`, and notes under S29 and S30 in `docs/SOURCE_INDEX.md`. Earlier on the branch (fd8523e): the two Access as a Superpower views, the showcase fixture and its README section, and the LabDemo, LabFeatures, and Mac hosted tests.

**Commands and results:** see the LAB-035-B rows in [BUILD_STATUS](../docs/BUILD_STATUS.md). `script/test.sh` and `python3 script/validate/all.py` passed at ab7c0b3.

**Platforms:** Mac passed through automated tests and the running app (fixture path, no person). iPhone: simulator only. Watch and TV: not applicable; LAB-035 has no Watch or TV target.

**Not run:** hands-on VoiceOver and Audio Graph, Voice Control, Full Keyboard Access (the iPhone also needs a hardware keyboard), the display-setting passes by a person, a physical iPhone, the Mac accessibility audit (UI automation asks for authentication on this Mac), iPad, and a 26-SDK compile.

**Follow-ups:** new finding 1 (each Audio Graph point's label repeats its value) and finding 2 (the Mac `StatusBadge` has no role); LAB-035-A findings 1 and 4 remain open; a committed UI-test target for `LabPhone-Core` and a Mac UI-test target.

**Next dependency-ready tickets:** none new on its own. LAB-045-A becomes ready once LAB-008-B lands; CORE-012 still waits on LAB-004-B, LAB-007-B, and LAB-008-B.
