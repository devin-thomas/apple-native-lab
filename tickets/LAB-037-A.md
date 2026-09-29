---
id: "LAB-037-A"
title: "Implement Home Scene Sandbox"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-037-A — Implement Home Scene Sandbox

## Goal

Preview a home-scene diff, execute only selected harmless actions, and explain partial failure.

## Authority and scope

Read the [governing specification](../experiments/LAB-037-home-scene-sandbox.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** home-scene-sandbox module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Use simulated lights first
3. Request access to the selected home
4. Preview on/off/brightness changes
5. Commit and report per-accessory outcomes
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] A disconnected lamp does not mark the whole scene successful.
- [ ] Locks, doors, alarms, and heating are excluded by default.
- [ ] A revoked home permission stops live mode.
- [ ] Fallback is usable: Deterministic fictional home with no real accessories..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** HomeKit does not expose every vendor API; Matter controller work is separate from a HomeKit client.

**Research:** [S44](../docs/SOURCE_INDEX.md#s44).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
