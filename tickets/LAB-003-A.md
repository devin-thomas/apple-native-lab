---
id: "LAB-003-A"
title: "Implement Shortcut Workbench"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B", "LAB-008-B"]
---

# LAB-003-A — Implement Shortcut Workbench

## Goal

Turn the lab into a small typed automation toolbox, not a collection of launch-app commands.

## Authority and scope

Read the [governing specification](../experiments/LAB-003-shortcut-workbench.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** shortcut-workbench module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Offer a curated entry set separate from atomic actions
3. Build import-query-transform-export recipe walkthroughs
4. Persist entity references in a user-created shortcut
5. Inspect data passed into optional model steps
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] A recipe survives renaming its source item.
- [ ] Cancellation does not leave half an import.
- [ ] Raw secret values never enter recipe exports.
- [ ] Fallback is usable: Manual recipe instructions and app action browser; no secret storage inside Shortcuts..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Up to ten curated App Shortcuts is not a ten-action library cap. Platform packaging differs; never auto-install a personal automation.

**Research:** [S03](../docs/SOURCE_INDEX.md#s03), [S04](../docs/SOURCE_INDEX.md#s04).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
