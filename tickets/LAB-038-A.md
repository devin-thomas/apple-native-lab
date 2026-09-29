---
id: "LAB-038-A"
title: "Implement Wallet Moment"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-038-A — Implement Wallet Moment

## Goal

Build an original event pass with a useful update story and an explicit signing boundary.

## Authority and scope

Read the [governing specification](../experiments/LAB-038-wallet-moment.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** wallet-moment module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Render a pass preview without signing
3. Validate the payload and barcode
4. Use an operator-supplied signing environment for a test pass
5. Inspect updates and expiration behavior
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] No pass-signing key enters a client or repo.
- [ ] A barcode is not treated as authorization by itself.
- [ ] Expired passes have an honest state.
- [ ] Fallback is usable: Local pass preview and sample event card..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Wallet passes are not payment credentials, government ID issuance, or unrestricted NFC/secure-element access.

**Research:** [S45](../docs/SOURCE_INDEX.md#s45).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
