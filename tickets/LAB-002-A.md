---
id: "LAB-002-A"
title: "Implement Context Cards"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-002-A — Implement Context Cards

## Goal

Ask about the visible object, then complete a small decision inside a system presentation.

## Authority and scope

Read the [governing specification](../experiments/LAB-002-context-cards.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** context-cards module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Associate one primary sample entity with its view
3. Map only genuinely matching Apple schemas
4. Render an interactive confirmation where supported
5. Resolve stale visible content without touching a different object
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] A replaced onscreen item cannot mutate the previous item.
- [ ] A schema mismatch fails the integration gate.
- [ ] Siri-disabled devices retain the same decision UI.
- [ ] Fallback is usable: In-app card and typed Shortcut remain complete; context resolution is explicitly unavailable..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No invented universal schema for arbitrary business nouns; Siri rollout and region are separate gates.

**Research:** [S02](../docs/SOURCE_INDEX.md#s02), [S03](../docs/SOURCE_INDEX.md#s03), [S64](../docs/SOURCE_INDEX.md#s64).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
