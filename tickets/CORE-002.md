---
id: "CORE-002"
title: "Implement the typed operation and receipt spine"
status: "planned"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-001"]
---

# CORE-002 — Implement the typed operation and receipt spine

## Goal

Make all system entry points share one deterministic, authorization-checked application service.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Packages/LabDomain and unit tests.

## Implementation steps

1. Define distinct stable identifier and revision types
2. Implement create/find/update/archive operations with explicit validation
3. Atomically persist idempotency and operation results through a store protocol
4. Return meaningful conflict/error receipts and bounded undo operations

## Acceptance criteria

- [ ] The same request ID and payload cannot mutate twice.
- [ ] A reused request ID with a different payload is refused.
- [ ] A stale revision returns an inspectable conflict.
- [ ] No caller bypasses the authorization policy by selecting a different adapter.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
