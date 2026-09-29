---
id: "LAB-001-A"
title: "Implement Action Atlas"
status: "planned"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008"]
---

# LAB-001-A — Implement Action Atlas

## Goal

Create a collection, find an item, mutate it, and inspect the same receipt from three entry points.

## Authority and scope

Read the [governing specification](../experiments/LAB-001-action-atlas.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** action-atlas module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Seed 12 original sample objects with stable UUIDs
3. Expose create/find/update/archive/export intents
4. Call the same operation from UI and Shortcuts
5. Show typed output and undo receipt
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Duplicate request IDs cause one mutation.
- [ ] Missing and ambiguous entities produce recoverable errors.
- [ ] UI and intent yield identical persisted state.
- [ ] Fallback is usable: A normal app action browser runs without Siri or Apple Intelligence..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** AppEntity is not arbitrary access to other apps. Domain operations remain authorization-checked.

**Research:** [S01](../docs/SOURCE_INDEX.md#s01), [S03](../docs/SOURCE_INDEX.md#s03), [S05](../docs/SOURCE_INDEX.md#s05).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
