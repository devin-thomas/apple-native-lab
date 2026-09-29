---
id: "LAB-005-A"
title: "Implement Live Session Beacon"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-004-B", "LAB-032-B"]
---

# LAB-005-A — Implement Live Session Beacon

## Goal

Follow a real finite export or rehearsal with a cancel button and honest progress.

## Authority and scope

Read the [governing specification](../experiments/LAB-005-live-session-beacon.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** live-session-beacon module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Start from an explicit user action
3. Publish coarse monotonic progress
4. End with success, failure, or cancellation
5. Provide privacy-safe compact and expanded layouts
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] No activity remains active after terminal state.
- [ ] Unknown total work is indeterminate, not fabricated percent.
- [ ] Force-quit/relaunch restores the job truth.
- [ ] Fallback is usable: In-app job panel and optional completion notification..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** A Live Activity is not a background worker or an unlimited widget refresh loophole.

**Research:** [S58](../docs/SOURCE_INDEX.md#s58), [S28](../docs/SOURCE_INDEX.md#s28).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
