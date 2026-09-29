---
id: "LAB-015"
title: "Local Model Bench"
state: "specified"
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

## Delivery

[Implementation ticket](../tickets/LAB-015-A.md) → [qualification ticket](../tickets/LAB-015-B.md).

**Lab dependencies:** [LAB-010](LAB-010-typed-local-intelligence.md).

**Primary-source references:** [S06](../docs/SOURCE_INDEX.md#s06), [S63](../docs/SOURCE_INDEX.md#s63). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
