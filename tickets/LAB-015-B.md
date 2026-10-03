---
id: "LAB-015-B"
title: "Qualify and document Local Model Bench"
status: "done"
milestone: "M3"
kind: "qualification"
depends_on: ["LAB-015-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-015-B — Qualify and document Local Model Bench

## Goal

Prove Local Model Bench on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-015-local-model-bench.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** local-model-bench tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Cold and warm results cannot be merged; A failed task cannot improve a performance score; A model too large for memory is refused before allocation
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [x] Cold and warm results cannot be merged (`BenchScoreTests.coldAndWarmResultsCannotBeMerged`; hosted four-phase replay).
- [x] A failed task cannot improve a performance score (`BenchScoreTests.aFailedTaskCannotImproveTheScore`, wrong answer at 1 ns; recorded failure has no median).
- [x] A model too large for memory is refused before allocation (`ModelGateTests.aModelLargerThanTheBudgetIsRefusedBeforeTheLoader`, 4 billion declared bytes against 1,000 bytes, zero loader calls).
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations (two fixture records at `22a9cf0`).
- [x] The walkthrough never claims a simulation is the live integration (static review; opens with fixture executor, not inference).
- [x] Only approved original/public-safe material enters screenshots and exports (two reviewed original-fixture JSON records; no screenshots or media).

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** Apple-silicon Mac; optional capable iPhone/iPad.

**Unavailable path:** Deterministic fixture executor benchmarks the pipeline, marked as not inference.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-015 stays `implemented`.** The complete fallback ran in package tests and the sandboxed Mac host on clean fixture stores. No model was loaded. The live route is explicitly unavailable, rather than blocked by signing or owner permission. Neither Mac hosting nor a simulator smoke build establishes inference or hardware performance.

**Evidence:** two records in `evidence/LAB-015/`, source `22a9cf0`. Corpus `lab-015-fixture-v1`, SHA-256 `529194c1d7b4ac56e975472adfd70e394b03995d8e82e0fd13966a5bef6a11ac`. The hosted cold-report digest is `7cc58957bec008d6671012f2da30ffacf9a5cf571fca1874dd655ea09723aa73`. Xcode 27.0 (27A266a), macOS SDK 27.0, Swift 6.4 (swiftlang-6.4.0.34.1), arm64 Mac Studio on macOS 27.0 (26A425). The package record is transcribed from the actual passing test output; the host record is the exported test attachment. Publication review approved both as `public-fixture`; no raw logs, identifiers, private paths, accounts, media, or screenshots were copied into the public tree.

**Replay:** `LocalModelBenchEvidenceTests.fourPhasesRecordRetryAndResetWithEvidence` starts a fresh SQLite library, creates an original user item standing in for imported data, runs Download, Warm-up, Measured cold, and Measured warm, checks four correct tasks in each, refuses scores for the first two, and refuses a combined cold/warm score. Cold is 31,000,000 ns and warm is 9,000,000 ns, fixture-script only; `BenchScore` deliberately uses the lower median (second sorted value for four samples). Record twice adds one item and no retry receipt. Reset twice archives that item once, leaves the user sample and demo items unchanged, and retains all four in-memory reports. No import adapter or UI control was driven in this replay.

**Failure and state cases:** existing package tests prove denied model-tool recording, reset without a grant, unavailable storage, cancellation before allocation, invalid corpus/script, unreviewed license, and failure scoring. New `BenchQualificationTests` proves a change between reset's read and commit returns a conflict and leaves the changed report active; a fresh reset archives it. Retrying identical report bytes after reset returns the original receipt and leaves the item archived. This is current behavior, not a new restore policy.

**Changed:** two test files (package qualification and Mac hosted evidence), two fixture evidence records, the walkthrough, experiment proof/qualification notes, the installed-SDK ledger and source note, accessibility review, this completion record, and BUILD_STATUS evidence rows. No production code, shared host hooks, project settings, entitlements, dependencies, capability profile, or behavior changed; no decision record is needed.

**SDK/source review:** read the installed Core ML interface through `labr` with `grep` (Research has no `rg`). Async `MLModel.load(contentsOf:configuration:)` remains macOS 12/iOS 15/watchOS 8/tvOS 15; `MLComputePlan.estimatedCost` returns an optional cost with unitless `Double` weight. Neither is called. Read Apple's load and compute-plan reference pages via their official documentation JSON endpoints after a failed Markdown fetch. Availability matches the SDK. The load page's return-value prose says `nil`, while its declaration is nonoptional `async throws`; the installed signature governs. The compute-plan overview estimates execution resources before predictions, but does not promise pre-load byte admission. No live path ran.

**Known limits:** the session uses total physical memory as its supplied budget, not free-memory telemetry; no real asset budget is measured. Reset's message counts conflict receipts as results, so inspect receipts before claiming an archive. Identical archived reports are not restored by recording again. Mac export is selectable JSON only; the phone has no export view. There is no report picker. Static accessibility review found missing dedicated run/record/reset menu commands, no explicit result announcement in this session, and no pinned phone action bar. Manual assistive-technology and rendering passes remain not-run.

**Commands actually run (Research through `labr`):**

- Toolchain queries and installed Core ML `grep` — succeeded; initial `rg` was unavailable.
- `swift test --package-path Packages/LabFeatures --filter LocalModelBenchTests` — 22 passed after correcting the new test backend's typed-error compile failure.
- Targeted `xcodebuild` for `LocalModelBenchEvidenceTests` and `LocalModelBenchHostTests`, with result bundle `build/LAB-015-B-host.xcresult` and `LAB_SOURCE_REVISION=22a9cf0` — 3 passed, no failures or skips. Exported the attachment with `xcrun xcresulttool export attachments`; read the summary with `get test-results summary`.
- `python3 script/generate_catalog.py` — succeeded; catalog content unchanged.
- `LAB_SIMULATOR_PREFIX="NL LAB-015-B" script/test.sh` — ran once. Validators 8/8, validator self-tests 93, and all package suites passed (LocalModelBench 22 again). The Mac suite failed in unrelated `RenderSurvivesHostTests.aRenderRunsAsTheMacWorkerWithEveryStepInTheReceiptList`: expected the receipt operations to end with `"Finish Job"`, but observed only `"Start Job"` and four `"Save Job Checkpoint"` entries. The result bundle identifies that single failure. No LAB-015 production source or rendering source changed; no unrelated repair or full-gate retry was attempted. The iPhone, Watch, TV simulator steps and release manifest were not reached.
- `python3 script/validate/all.py` after the completion documentation — passed 8/8, including 32 evidence records and the unchanged generated catalog.

**Not run:** physical iPhone/iPad, any live inference, model asset download, memory pressure, peak model memory, thermal readings, hardware latency, experiment UI in the iOS simulator, VoiceOver, Voice Control, Full Keyboard Access, rendered large-text/contrast/motion passes, and a 26-family SDK compile. Watch and TV have no bench surface. Owner work is needed for any optional physical mobile evidence; a future live adapter needs separate implementation and reviewed assets before qualification.

**Next dependency-ready ticket:** LAB-029-B (LAB-029-A, CORE-007, CORE-009, and CORE-010 are done); no work on it was performed.
