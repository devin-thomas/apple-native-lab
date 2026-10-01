---
id: "LAB-015-A"
title: "Implement Local Model Bench"
status: "done"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-010-B"]
---

# LAB-015-A — Implement Local Model Bench

## Goal

Compare small local tasks across machines with correctness, latency, memory, and thermal evidence rather than a flashy token counter.

## Authority and scope

Read the [governing specification](../experiments/LAB-015-local-model-bench.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** local-model-bench module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Use an original fixed evaluation corpus
3. Separate download, warm-up, and measured runs
4. Check model license and memory budget before loading
5. Export reproducible results with environment metadata
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Cold and warm results cannot be merged. (`BenchScoreTests.coldAndWarmResultsCannotBeMerged`: cold median 31_000_000 ns and warm median 9_000_000 ns, and `BenchScore(reports:)` throws `mixedThermal`. The Mac host test runs both and gets the same throw. Download and warm-up are not scores.)
- [x] A failed task cannot improve a performance score. (`BenchScoreTests.aFailedTaskCannotImproveTheScore`: a 1 ns failure throws `failedTask`, and the passing score stays 31_000_000 ns. A stored failure's note says "No score." and does not say "median".)
- [x] A model too large for memory is refused before allocation. (`ModelGateTests.aModelLargerThanTheBudgetIsRefusedBeforeTheLoader`: 4_000_000_000 bytes against 1_000 available throws `exceedsMemory` and the loader is called 0 times. An unreviewed license is refused the same way. The fixture loader reports `allocatedBytes` 0.)
- [x] Fallback is usable: Deterministic fixture executor benchmarks the pipeline, marked as not inference. (`FixtureExecutorTests.theFixtureRunCompletesAndIsNotInference`: four corpus cases pass, `inference` is false, `executor` is `fixture`, `timebase` is `fixture-script`, `thermalSensor` is `not-observed`. `LiveModelBench.run()` throws `liveModelUnavailable` and the fixture run still completes. The Mac host test records a cold run through the app.)
- [x] Sensitive operations share the domain authorization/receipt path. (Record and reset go through `OperationService`. A retry returns the same create-item receipt. A model tool is `unauthorized` and writes nothing. Reset without a grant leaves the report in place. Reset with a grant archives only the bench report; a demo item and another user item stay. The Mac host test's create and archive receipts are App UI.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No promise that any model runs on every M-series Mac; optional dependencies are isolated and pinned.

**Research:** [S06](../docs/SOURCE_INDEX.md#s06), [S63](../docs/SOURCE_INDEX.md#s63).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-015's spec now claims `implemented`. The fixture executor ran in package tests and in the Mac host. No model was loaded. Nothing here is device-verified, and the iPhone screen was not driven.

**Changed:**

- `Packages/LabFeatures`: the `LocalModelBench` product and target, depending only on LabDomain. It holds the corpus, `ModelGate`, `FixtureExecutor`, `BenchScore`, `BenchReport`, and `BenchRecorder`. Tests: `LocalModelBenchTests` (20 tests). `LabCatalogTests` now expect seven implemented experiments.
- `Apps/Shared/LocalModelBench/` (new): `LocalModelBenchSession`, `LibraryBenchBackend`, the page, and the catalog entry.
- `Apps/Mac/Window/LocalModelBenchColumns.swift` (new).
- Hooks in shared host files, one case each:
  - `MainWindowState` has the destination and the per-window session.
  - `MainWindow` has the columns and the search prompt.
  - `SidebarView` has the row.
  - `LabCommands` has View › Local Model Bench (⌘9).
  - `ExperimentDetailView` has the Open Local Model Bench entry.
- `project.yml` and the regenerated project: LabMac, LabPhone, and LabPhoneSurfaces link `LocalModelBench`. No new entitlement. Core ML is not linked. Regenerated with XcodeGen 2.46.0.
- `experiments/LAB-015-local-model-bench.md`: `state: implemented`, the implemented split, and implementation notes. The Fallback paragraph is unchanged. The catalog JSON was regenerated.
- `docs/SOURCE_INDEX.md` and `docs/VERIFICATION_BOUNDARIES.md`: the installed Core ML signatures, recorded as read and not called.
- `Tests/LabMacTests/LocalModelBenchHostTests.swift` (new).
- This record, and rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** The macOS 27.0 SDK's Core ML interface has `MLModel.load(contentsOf:configuration:)` and `MLComputePlan.estimatedCost(of:)`, which returns a unitless weight after loading an asset. No byte budget is available before a load. Foundation Models has no evaluation harness. The module imports neither, and MLX is not a dependency.
2. **Corpus.** Four original cases, id `lab-015-fixture-v1`. The export's corpus digest is the SHA-256 of their canonical JSON.
3. **Phases.** Download, warm-up, and measured are separate runs. Cold and warm measured runs keep separate scores.
4. **License and memory.** Only the fixture license is accepted. `declaredMemoryBytes` must be greater than zero and no larger than the caller's available bytes. The loader closure runs only after both checks.
5. **Export.** Sorted-key JSON with the executor, `inference: false`, the fixture timebase, `thermalSensor: not-observed`, and the operating-system string the caller supplies. Two runs of the same inputs match byte for byte.
6. **Tests.** The domain operation, cancellation (`cancellationBeforeTheLoaderAllocatesNothing`, loader called 0 times), invalid input (empty corpus, unknown script, blank case), and the unavailable path (`LiveModelBench.run()`, a closed backend, and a model tool).

**Commands run (research via `labr`):**

- `swift test --package-path Packages/LabFeatures --filter LocalModelBenchTests` — 20 passed
- `swift test --package-path Packages/LabFeatures --filter LabCatalogTests` — 14 passed
- `xcodebuild … -only-testing:LabMacTests/LocalModelBenchHostTests test` — 2 passed
- `python3 script/validate/all.py` — 8 of 8
- `LAB_SIMULATOR_PREFIX="NL LAB-015-A" script/test.sh` — packages and Mac passed; first iPhone boot timed out at 60 s under load
- iPhone, Watch, and TV host smoke tests plus `python3 script/build_manifest.py` on retry — passed

**Not run:**

- A physical device, and any Core ML or Foundation Models load.
- The iPhone screen. The phone host links the module; its UI was not driven.
- VoiceOver, Voice Control, and Full Keyboard Access.
- A 26-SDK compile.
- A hardware latency, memory, or thermal measurement. Fixture nanoseconds are a script, and the thermal sensor is `not-observed`.
