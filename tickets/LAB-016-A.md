---
id: "LAB-016-A"
title: "Implement Pick Up Here"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-016-A — Implement Pick Up Here

## Goal

Move a draft to another device and resume at the exact selected section without pretending Handoff is file sync.

## Authority and scope

Read the [governing specification](../experiments/LAB-016-pick-up-here.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** pick-up-here module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Advertise a small resumable activity
3. Transfer only identifiers and position
4. Resolve or request the underlying document
5. Handle a newer revision on the destination
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Missing document prompts import instead of empty success.
- [ ] Revoked access does not reveal old content.
- [ ] A changed document clamps the saved position safely.
- [ ] Fallback is usable: Copy an explicit continuation link or document..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Handoff is a continuation hint, not guaranteed bulk transfer or instant background execution.

**Research:** [S60](../docs/SOURCE_INDEX.md#s60).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
