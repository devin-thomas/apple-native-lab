---
id: "LAB-021-A"
title: "Implement Wrist Relay"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B", "LAB-019-B"]
---

# LAB-021-A — Implement Wrist Relay

## Goal

Tap a small wrist control and see a durable acknowledgement, even when delivery must wait.

## Authority and scope

Read the [governing specification](../experiments/LAB-021-wrist-relay.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** wrist-relay module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Use immediate messages only when reachable
3. Use queued transfer for durable events
4. Show pending, acknowledged, failed, and expired states
5. Keep complications glanceable and safe when locked
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Ten repeated transport deliveries produce one mutation.
- [ ] A haptic acknowledgement is not shown before the intended stage.
- [ ] Unreachable phone retains a bounded queue.
- [ ] Fallback is usable: Phone control pad and a Watch simulator preview..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** The Watch is not an always-on streaming process; no fake workout session to keep it alive.

**Research:** [S19](../docs/SOURCE_INDEX.md#s19).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
