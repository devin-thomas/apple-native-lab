---
id: "LAB-004-A"
title: "Implement Surface Deck"
status: "planned"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-004-A — Implement Surface Deck

## Goal

One reversible session state appears in a widget, a Control, and the main app.

## Authority and scope

Read the [governing specification](../experiments/LAB-004-surface-deck.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** surface-deck module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Build small/medium widgets from immutable snapshots
3. Expose one toggle and one launch action
4. Let users add Controls and map supported hardware triggers
5. Refresh by documented policy rather than a live polling timer
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Stale widget toggles reconcile to current state.
- [ ] Locked-device view redacts private labels.
- [ ] A denied update budget leaves a correct stale indicator.
- [ ] Fallback is usable: Main-app state deck and static widget previews..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Widget/Control availability is per platform. An iPhone Action button does not imply a Watch Action button.

**Research:** [S01](../docs/SOURCE_INDEX.md#s01), [S59](../docs/SOURCE_INDEX.md#s59).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
