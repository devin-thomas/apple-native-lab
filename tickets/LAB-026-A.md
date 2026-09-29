---
id: "LAB-026-A"
title: "Implement Camera Instrument Panel"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-012-B"]
---

# LAB-026-A — Implement Camera Instrument Panel

## Goal

Show segmentation, OCR, and simple pose landmarks as instruments with visible confidence and frame timing.

## Authority and scope

Read the [governing specification](../experiments/LAB-026-camera-instrument-panel.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** camera-instrument-panel module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Choose one analysis mode at a time
3. Downsample with a documented budget
4. Show evidence overlays in app
5. Drop old frames rather than build a lagging queue
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Backpressure limits queue depth.
- [ ] Permission denial keeps sample-frame inspection usable.
- [ ] No person identity or sensitive trait is inferred.
- [ ] Fallback is usable: Original sample frames and explicit image import..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Not access to camera streams owned by another app and not an always-recording assistant.

**Research:** [S55](../docs/SOURCE_INDEX.md#s55), [S41](../docs/SOURCE_INDEX.md#s41).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
