---
id: "CORE-007"
title: "Establish automated tests and evidence discipline"
status: "planned"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-001", "CORE-002", "CORE-004"]
---

# CORE-007 — Establish automated tests and evidence discipline

## Goal

Make every future claim traceable to an actual test path.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Tests, future CI workflows, evidence utilities.

## Implementation steps

1. Create unit and adapter test targets with deterministic fixtures
2. Implement a structured evidence record and status vocabulary
3. Add Markdown links, ticket dependencies, and schema checks to CI
4. Keep public PR tests unsigned and without secrets or private runners

## Acceptance criteria

- [ ] CI can distinguish not-run/blocked from passed.
- [ ] A simulated result cannot be labeled physical-device proof.
- [ ] A broken local documentation link or dependency cycle fails validation.
- [ ] Fork PR execution has no signing credentials or personal-data access.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
