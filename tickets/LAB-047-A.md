---
id: "LAB-047-A"
title: "Implement Accessory Without a Factory"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-019-B", "LAB-041-B"]
---

# LAB-047-A — Implement Accessory Without a Factory

## Goal

Give a tiny button/light peripheral a polished pairing, control, and firmware-version story.

## Authority and scope

Read the [governing specification](../experiments/LAB-047-accessory-without-a-factory.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** accessory-without-a-factory module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Begin with a simulated device contract
3. Pair one explicitly supported peripheral
4. Expose safe, reversible commands
5. Handle rename, removal, and offline state
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Unknown firmware is refused or restricted.
- [ ] Unpairing invalidates the app trust record.
- [ ] A BLE-only device is never advertised as Wi-Fi Aware capable.
- [ ] Fallback is usable: Software peripheral simulator and a contract-level test suite..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No hardware purchase is required for baseline; vendor SDK, MFi, and Aware support cannot be assumed.

**Research:** [S31](../docs/SOURCE_INDEX.md#s31), [S32](../docs/SOURCE_INDEX.md#s32).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
