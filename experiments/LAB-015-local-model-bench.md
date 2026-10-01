---
id: "LAB-015"
title: "Local Model Bench"
state: "implemented"
milestone: "M3"
category: "Intelligence"
depends_on: ["LAB-010"]
source_review: "2026-09-29"
---

# LAB-015 — Local Model Bench

## The moment

Compare small local tasks across machines with correctness, latency, memory, and thermal evidence rather than a flashy token counter.

## Scope and native leverage

**Hosts:** Apple-silicon Mac; optional capable iPhone/iPad.

**Primary APIs:** Core ML, optional MLX/provider bridge, Foundation Models evaluation. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** BenchmarkCase, ModelDescriptor, RunMeasurement. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Use an original fixed evaluation corpus
2. Separate download, warm-up, and measured runs
3. Check model license and memory budget before loading
4. Export reproducible results with environment metadata

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Cold and warm results cannot be merged.
- [ ] A failed task cannot improve a performance score.
- [ ] A model too large for memory is refused before allocation.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No promise that any model runs on every M-series Mac; optional dependencies are isolated and pinned.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Deterministic fixture executor benchmarks the pipeline, marked as not inference.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/local-model-bench/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-015-A):

- `Packages/LabFeatures/Sources/LocalModelBench/` holds the corpus, the license and memory gate, the fixture executor, the score rules, and the recorder. It depends on LabDomain and never holds the store. It does not import Core ML, Foundation Models, or MLX.
- `Apps/Shared/LocalModelBench/` holds the session, `LibraryBenchBackend` (commits through `LabLibrary.submit`), and the iPhone screen. The Mac reaches it from the sidebar and View › Local Model Bench (⌘9). The iPhone reaches it from this experiment's catalog page, with no new tab.

## Implementation notes (LAB-015-A)

Observed with Xcode 27.0 (27A266a) and the macOS 27.0 SDK. These are package tests and Mac hosted tests, not device proof, and not a claim that a model ran.

- **No model load.** `MLModel.load(contentsOf:configuration:)` (macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0) loads a compiled model from a URL. `MLComputePlan.load` (macOS 14.4, iOS 17.4, watchOS 10.4, tvOS 17.4) also reads an asset, and `estimatedCost(of:)` returns a unitless `weight`, not a byte budget. Nothing in that interface reports bytes before a load. This build does not call either one, and it does not link Core ML. Foundation Models has no evaluation type this bench calls; the word "evaluate" in that interface is the profile builder, not a harness. MLX is not a dependency.
- **Gate.** A descriptor with an unreviewed license, or with `declaredMemoryBytes` above the caller's available bytes, throws before the loader closure runs. The fixture descriptor is 1 MiB and the fixture loader reports `allocatedBytes` 0.
- **Phases.** Download, warm-up, and measured are separate runs. A score exists only for a measured run whose every task passed, and only inside one thermal class. Cold and warm throw `mixedThermal`. A failed task throws `failedTask`; its latency is not a median.
- **Fixture.** The executor compares each case to the corpus's expected text. Every report has `inference: false`, `executor: "fixture"`, `timebase: "fixture-script"`, and `thermalSensor: "not-observed"`. The same inputs export the same JSON.
- **Receipts.** Record creates a user collection and one item through `OperationService`. A retry of the same report returns the original receipt. Reset archives only items in that collection whose extras are a bench report, and only with a grant. A model tool is refused and writes nothing. The lab's own Reset Demo does not remove user items.

## Delivery

[Implementation ticket](../tickets/LAB-015-A.md) → [qualification ticket](../tickets/LAB-015-B.md).

**Lab dependencies:** [LAB-010](LAB-010-typed-local-intelligence.md).

**Primary-source references:** [S06](../docs/SOURCE_INDEX.md#s06), [S63](../docs/SOURCE_INDEX.md#s63). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
