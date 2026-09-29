---
id: "LAB-022-A"
title: "Implement Proximity Instrument"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-019-B", "LAB-021-B"]
---

# LAB-022-A — Implement Proximity Instrument

## Goal

Watch an instrument respond to measured distance, confidence, and unavailable direction—not invented radar.

## Authority and scope

Read the [governing specification](../experiments/LAB-022-proximity-instrument.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** proximity-instrument module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Exchange session tokens through authenticated transport
3. Probe distance and direction separately
4. Render a confidence-aware instrument
5. Stop when the session loses authorization or foreground eligibility
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Direction-not-supported never renders a compass arrow.
- [ ] Signal loss freezes no misleading current distance.
- [ ] No nearby stranger is tracked without joining.
- [ ] Fallback is usable: Manual distance slider or prerecorded synthetic measurements, prominently labeled..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No AirTag inventory, Find My database access, or assumption that Watch ranging equals phone ranging.

**Research:** [S18](../docs/SOURCE_INDEX.md#s18).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
