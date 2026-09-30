---
id: "CORE-012"
title: "Qualify the complete first six-lab journey"
status: "in-progress"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-006", "CORE-007", "CORE-008", "CORE-009", "CORE-010", "LAB-001-B", "LAB-004-B", "LAB-007-B", "LAB-008-B", "LAB-010-B", "LAB-035-B"]
---

# CORE-012 — Qualify the complete first six-lab journey

## Goal

Prove the lab as a coherent app before growing the catalog into advanced experiments.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** M1 integration tests, showcase route, compatibility/evidence records.

## Implementation steps

1. Run the source/import → proposal/manual review → commit → query → surface journey
2. Exercise model unavailable, permission denied, duplicate import, stale state, and cancellation
3. Validate both physical supported adapters and the complete CoreLocal alternate route
4. Record tested hardware/OS and explicitly untested profiles

## Acceptance criteria

- [ ] One shared object remains consistent across every tested entry point.
- [ ] The manual path completes the entire workflow without cloud inference.
- [ ] A demo reset preserves user-imported data.
- [ ] No optional feature failure becomes a crash or unexplained dead end.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
