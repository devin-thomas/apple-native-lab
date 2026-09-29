---
id: "LAB-030-A"
title: "Implement Tactile Grammar"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-004-B"]
---

# LAB-030-A — Implement Tactile Grammar

## Goal

Design three distinguishable tactile cues and compare actual device output rather than treating haptics as decoration.

## Authority and scope

Read the [governing specification](../experiments/LAB-030-tactile-grammar.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** tactile-grammar module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Create success/warning/timing cues with original audio
3. Show visual and spoken equivalents
4. Route to supported device feedback
5. Provide a clear stop and intensity preference
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Unsupported actuators never crash a cue.
- [ ] Muted haptics leave every task usable.
- [ ] Repeated cues obey rate and fatigue limits.
- [ ] Fallback is usable: Visual pulse and optional quiet audio..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No arbitrary custom waveform parity on Watch; controller support differs by device.

**Research:** [S49](../docs/SOURCE_INDEX.md#s49), [S50](../docs/SOURCE_INDEX.md#s50).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
