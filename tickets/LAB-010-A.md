---
id: "LAB-010-A"
title: "Implement Typed Local Intelligence"
status: "planned"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-010-A — Implement Typed Local Intelligence

## Goal

Turn an ambiguous note into a typed proposal, then let a deterministic operation perform the approved change.

## Authority and scope

Read the [governing specification](../experiments/LAB-010-typed-local-intelligence.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** typed-local-intelligence module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Probe model readiness and language support
3. Generate a constrained draft from a bundled text fixture
4. Validate lengths, values, and cross-field rules
5. Preview the diff before commit
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Model-unavailable paths remain usable.
- [ ] Malicious imported instructions cannot authorize tools.
- [ ] Generated-but-invalid values never reach persistence.
- [ ] Fallback is usable: Deterministic sample parser and manual editor clearly labeled as non-model paths..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Structured generation constrains form, not factual truth. No hidden network fallback or billing.

**Research:** [S06](../docs/SOURCE_INDEX.md#s06).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
