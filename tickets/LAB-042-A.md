---
id: "LAB-042-A"
title: "Implement Desktop Native Power"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B", "LAB-008-B"]
---

# LAB-042-A — Implement Desktop Native Power

## Goal

Use a command palette, menu-bar status, multiwindow documents, and one deliberate automation entry point.

## Authority and scope

Read the [governing specification](../experiments/LAB-042-desktop-native-power.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** desktop-native-power module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Use native window/menu/keyboard conventions
3. Add a Services-style selected-text import
4. Expose an allowlisted scriptable operation if appropriate
5. Restore scene state without reopening private content unexpectedly
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Every gesture-only action has a discoverable alternate path.
- [ ] Closing a window does not destroy its document.
- [ ] No arbitrary shell text is executed from an intent.
- [ ] Fallback is usable: Standard menu command and file import..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Desktop scripting is a separate permission boundary, not a cross-platform universal ability.

**Research:** [S57](../docs/SOURCE_INDEX.md#s57), [S38](../docs/SOURCE_INDEX.md#s38).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
