---
id: "LAB-048-A"
title: "Implement Commercial Frontier Desk"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-041-B"]
---

# LAB-048-A — Implement Commercial Frontier Desk

## Goal

Learn how a public app reaches privileged system surfaces without treating entitlements as magic flags.

## Authority and scope

Read the [governing specification](../experiments/LAB-048-commercial-frontier-desk.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** commercial-frontier-desk module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Provide three tiny independent lifecycle probes
3. PTT: model channel join/leave before any live APNs server
4. CarPlay: build an allowed-category simulator view
5. Screen Time: self-authorized demo with clear revocation
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Missing managed approval does not break other targets.
- [ ] No PTT wake is used for unrelated work.
- [ ] Screen Time has a documented self-escape and never hides restrictions.
- [ ] Fallback is usable: In-app protocol/lifecycle demonstrators labeled as simulations..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Three bounded spikes, not three production products. Real PTT networking and managed distribution approvals are external gates.

**Research:** [S34](../docs/SOURCE_INDEX.md#s34), [S35](../docs/SOURCE_INDEX.md#s35), [S36](../docs/SOURCE_INDEX.md#s36).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
