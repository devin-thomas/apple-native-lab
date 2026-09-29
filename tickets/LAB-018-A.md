---
id: "LAB-018-A"
title: "Implement Together Mode"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-019-B", "LAB-031-B"]
---

# LAB-018-A — Implement Together Mode

## Goal

Invite another person into the same media inspection or drawing activity with late-join recovery.

## Authority and scope

Read the [governing specification](../experiments/LAB-018-together-mode.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** together-mode module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Require explicit SharePlay activation
3. Synchronize state and participant roles
4. Make each participant resolve authorized media
5. Support pause, leave, and resynchronization
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Late join receives a complete state snapshot.
- [ ] A guest cannot perform owner-only destructive actions.
- [ ] Content rights failure does not fall back to streaming protected bytes.
- [ ] Fallback is usable: Local two-window simulation labeled as simulated; ordinary playback still works..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** SharePlay is not arbitrary serverless background sync and does not grant media licenses.

**Research:** [S16](../docs/SOURCE_INDEX.md#s16), [S41](../docs/SOURCE_INDEX.md#s41).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
