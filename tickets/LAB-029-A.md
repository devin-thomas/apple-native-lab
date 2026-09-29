---
id: "LAB-029-A"
title: "Implement Audio Workshop"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-029-A — Implement Audio Workshop

## Goal

Build a tiny usable audio processor with a inspectable graph, MIDI control, and an optional plugin form.

## Authority and scope

Read the [governing specification](../experiments/LAB-029-audio-workshop.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** audio-workshop module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Start with gain/filter and original loops
3. Make bypass and panic-mute always reachable
4. Map one MIDI parameter
5. Package a separate AUv3 only after standalone validation
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] No allocation or blocking I/O in render callbacks.
- [ ] Output route and sample-rate changes recover.
- [ ] Plugin state round-trips across host reload.
- [ ] Fallback is usable: Offline audio-file processing and on-screen MIDI events..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No automatic gain jumps, phantom-power control, or promise of compatibility with every proprietary audio interface.

**Research:** [S41](../docs/SOURCE_INDEX.md#s41), [S56](../docs/SOURCE_INDEX.md#s56).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
