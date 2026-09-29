---
id: "LAB-045-A"
title: "Implement Ink Has Structure"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B", "LAB-035-B"]
---

# LAB-045-A — Implement Ink Has Structure

## Goal

Annotate an object and keep the ink as editable data rather than flattening everything to a screenshot.

## Authority and scope

Read the [governing specification](../experiments/LAB-045-ink-has-structure.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** ink-has-structure module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Draw on original sample media
3. Persist editable ink with document IDs
4. Provide erase/undo and semantic text alternatives
5. Export flattened preview separately from native data
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Undo preserves anchoring after document resize.
- [ ] Non-Pencil users complete the task.
- [ ] Unsupported pencil gestures are absent, not broken.
- [ ] Fallback is usable: Mouse/touch annotations and typed notes..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No iPad purchase required; advanced Pencil hardware features remain hardware-gated.

**Research:** [S53](../docs/SOURCE_INDEX.md#s53).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
