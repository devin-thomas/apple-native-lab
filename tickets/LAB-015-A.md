---
id: "LAB-015-A"
title: "Implement Local Model Bench"
status: "planned"
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

- [ ] Cold and warm results cannot be merged.
- [ ] A failed task cannot improve a performance score.
- [ ] A model too large for memory is refused before allocation.
- [ ] Fallback is usable: Deterministic fixture executor benchmarks the pipeline, marked as not inference..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No promise that any model runs on every M-series Mac; optional dependencies are isolated and pinned.

**Research:** [S06](../docs/SOURCE_INDEX.md#s06), [S63](../docs/SOURCE_INDEX.md#s63).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
