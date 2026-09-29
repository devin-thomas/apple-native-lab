---
id: "LAB-017-A"
title: "Implement Durable Sync Ledger"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-017-A — Implement Durable Sync Ledger

## Goal

Edit offline on two devices, reconnect, and explain exactly how the final state was chosen.

## Authority and scope

Read the [governing specification](../experiments/LAB-017-durable-sync-ledger.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** durable-sync-ledger module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Maintain a local write-ahead mutation ledger
3. Sync private/shared records in an optional service profile
4. Surface conflicts instead of silently overwriting
5. Test account switching and disabled iCloud
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Conflicting edits remain inspectable.
- [ ] Deleting and reinstalling does not resurrect tombstoned data accidentally.
- [ ] Account A data never appears in account B.
- [ ] Fallback is usable: Local store plus manual document exchange..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** CloudKit synchronization is opportunistic, not a low-latency event bus. Never sync personal fixtures to a public database.

**Research:** [S15](../docs/SOURCE_INDEX.md#s15).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
