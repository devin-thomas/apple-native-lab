---
id: "LAB-006-A"
title: "Implement Find the Thing"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B", "LAB-010-B"]
---

# LAB-006-A — Implement Find the Thing

## Goal

Search a deliberately messy local collection and see exactly which owned records informed the answer.

## Authority and scope

Read the [governing specification](../experiments/LAB-006-find-the-thing.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** find-the-thing module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Index only opted-in lab records
3. Return stable IDs and deep links
4. Offer lexical search before optional semantic retrieval
5. Delete and reindex with auditable counts
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Deleted private data is removed from the app index.
- [ ] An unsupported query returns no invented results.
- [ ] A generated answer cites actual record IDs.
- [ ] Fallback is usable: Lexical in-app search with the same result model..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No assumption of global Spotlight access to other apps or the entire Mac.

**Research:** [S02](../docs/SOURCE_INDEX.md#s02), [S06](../docs/SOURCE_INDEX.md#s06).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
