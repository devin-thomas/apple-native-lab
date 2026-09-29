---
id: "LAB-019-A"
title: "Implement Local Constellation"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-019-A — Implement Local Constellation

## Goal

Use a Mac as conductor, a phone as controller, and a television as a stateful display without an internet server.

## Authority and scope

Read the [governing specification](../experiments/LAB-019-local-constellation.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** local-constellation module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Pair explicitly using a short code plus pinned peer identity
3. Negotiate role and protocol version
4. Separate reliable commands from replaceable samples
5. Measure clock error, sequence gaps, and reconnection
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] A stale command is ignored or explicitly reconciled.
- [ ] An unpaired peer sees no session data.
- [ ] A disconnected client visibly becomes stale.
- [ ] Fallback is usable: Single-device conductor/client simulation with identical wire messages..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Local network availability and permissions are required. No arbitrary remote shell, unattended wake, or hard real-time claim.

**Research:** [S61](../docs/SOURCE_INDEX.md#s61).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
