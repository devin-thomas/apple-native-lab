---
id: "LAB-023-A"
title: "Implement Tabletop Reality"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-023-A — Implement Tabletop Reality

## Goal

Place a small interactive system on a real table, move around it, and inspect occlusion and tracking quality.

## Authority and scope

Read the [governing specification](../experiments/LAB-023-tabletop-reality.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** tabletop-reality module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Acquire a plane with coaching UI
3. Place original procedural objects
4. Persist only supported mapping data with consent
5. Recover from relocalization failure
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Tracking loss suspends precision interactions.
- [ ] A reset destroys only lab-owned anchors.
- [ ] An accessibility list exposes every meaningful object.
- [ ] Fallback is usable: Orbitable 3D scene with mouse/touch controls..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Handheld AR, not headset passthrough or guaranteed persistent world tracking.

**Research:** [S40](../docs/SOURCE_INDEX.md#s40).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
