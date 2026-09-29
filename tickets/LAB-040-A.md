---
id: "LAB-040-A"
title: "Implement Commerce Without Tricks"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-040-A — Implement Commerce Without Tricks

## Goal

Exercise buy, restore, refund, pending approval, and offline entitlement states using test products.

## Authority and scope

Read the [governing specification](../experiments/LAB-040-commerce-without-tricks.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** commerce-without-tricks module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Start exclusively with local StoreKit configuration
3. Present truthful product names and terms
4. Verify transaction state before entitlement
5. Exercise restore and revocation
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] No button in the default build creates a real charge.
- [ ] Unverified transactions grant nothing.
- [ ] Restoration does not require a private developer account.
- [ ] Fallback is usable: Local transaction-state simulator..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** The lab itself stays free; shipping commerce requires current policy review and appropriate product classification.

**Research:** [S46](../docs/SOURCE_INDEX.md#s46).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
