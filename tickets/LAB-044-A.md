---
id: "LAB-044-A"
title: "Implement Play Together Native"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-019-B", "LAB-030-B"]
---

# LAB-044-A — Implement Play Together Native

## Goal

Play a tiny original cooperative challenge with real identity/match lifecycle and a local fallback.

## Authority and scope

Read the [governing specification](../experiments/LAB-044-play-together-native.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** play-together-native module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Build local two-player mode first
3. Add optional Game Center authentication
4. Synchronize a small authoritative state
5. Handle participant leave and replay
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Authentication refusal preserves local play.
- [ ] Replayed input cannot duplicate rewards.
- [ ] Controller loss is recoverable without app restart.
- [ ] Fallback is usable: Local shared-device or LAN play..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No third-party game hooks, cheating assistance, or promise of esports-grade netcode from a sample.

**Research:** [S51](../docs/SOURCE_INDEX.md#s51), [S49](../docs/SOURCE_INDEX.md#s49).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
