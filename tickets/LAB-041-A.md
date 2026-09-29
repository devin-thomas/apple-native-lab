---
id: "LAB-041-A"
title: "Implement Trust Desk"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-041-A — Implement Trust Desk

## Goal

Authorize a sensitive local action and inspect how a passkey flow differs from just unlocking an app.

## Authority and scope

Read the [governing specification](../experiments/LAB-041-trust-desk.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** trust-desk module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Protect a selected operation with local authorization
3. Store secrets only in scoped Keychain records
4. Model passkey registration/authentication against a fixture server
5. Expire and revoke grants
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] A display-name change cannot change identity.
- [ ] Biometric failure retains a non-destructive recovery path.
- [ ] Passkeys are never misrepresented as exportable app secrets.
- [ ] Fallback is usable: Local authorization and a clearly labeled passkey protocol simulation..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** LocalAuthentication is not remote account authentication. Production passkeys require a relying party and domain configuration.

**Research:** [S47](../docs/SOURCE_INDEX.md#s47).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
