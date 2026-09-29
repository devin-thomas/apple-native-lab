---
id: "LAB-036-A"
title: "Implement Workout Session Mirror"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-021-B"]
---

# LAB-036-A — Implement Workout Session Mirror

## Goal

Observe a clearly consented test workout on Watch and phone while preserving a fully synthetic learning mode.

## Authority and scope

Read the [governing specification](../experiments/LAB-036-workout-session-mirror.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** workout-session-mirror module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Default to synthetic samples
3. Request narrow health access only for live mode
4. Start a real user-requested workout
5. Mirror session controls and stop cleanly
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] No denied health field is treated as zero.
- [ ] Live samples cannot enter public fixtures.
- [ ] Stop ends the actual workout session.
- [ ] Fallback is usable: Synthetic replay supports the complete UI without HealthKit access..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No medical conclusions or fake workouts used as a background entitlement workaround.

**Research:** [S43](../docs/SOURCE_INDEX.md#s43), [S19](../docs/SOURCE_INDEX.md#s19).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
