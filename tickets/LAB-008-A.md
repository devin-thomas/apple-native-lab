---
id: "LAB-008-A"
title: "Implement Portable Objects"
status: "planned"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-008-A — Implement Portable Objects

## Goal

Drag a rich lab object into another window or export it as a inspectable document.

## Authority and scope

Read the [governing specification](../experiments/LAB-008-portable-objects.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** portable-objects module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Provide native document, JSON, text, and URL representations where meaningful
3. Show an export preview with fields and destination
4. Validate imports before committing
5. Preserve unknown fields in a versioned extras map
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Unicode and empty optional fields round-trip.
- [ ] A path-traversal attachment is rejected.
- [ ] Reimporting one document does not duplicate stable items.
- [ ] Fallback is usable: File picker and explicit export preserve the full native document..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Transfer representations are adapters, not automatic clipboard parity on every platform.

**Research:** [S11](../docs/SOURCE_INDEX.md#s11), [S12](../docs/SOURCE_INDEX.md#s12).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
